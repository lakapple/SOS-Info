import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/local/db_helper.dart';
import '../../data/models/rescue_message.dart';
import '../../data/models/extracted_info.dart';
import '../../data/remote/gemini_service.dart';
import '../../data/remote/rescue_api_service.dart';
import 'settings_provider.dart';

// State
class SmsState {
  final List<RescueMessage> sosList;
  final List<RescueMessage> otherList;
  final bool isLoading;
  SmsState({this.sosList = const [], this.otherList = const [], this.isLoading = true});
}

// Notifier
class SmsNotifier extends StateNotifier<SmsState> {
  final Ref ref;
  final Telephony _telephony = Telephony.instance;
  final List<RescueMessage> _queue = [];
  bool _isQueueRunning = false;
  Timer? _pollingTimer;

  SmsNotifier(this.ref) : super(SmsState()) {
    ref.onDispose(() => _pollingTimer?.cancel());
  }

  static void bgHandler(SmsMessage m) {}

  Future<void> init() async {
    // Permission Check
    final status = await [Permission.sms, Permission.location].request();
    if (status[Permission.sms] != PermissionStatus.granted) {
      state = SmsState(isLoading: false);
      return;
    }

    // Listener
    _telephony.listenIncomingSms(
      onNewMessage: (m) => _handleIncoming(m),
      onBackgroundMessage: bgHandler
    );

    await _loadFromDevice();
    
    // Polling Backup (every 15s)
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadFromDevice(silent: true));
  }

  // --- CORE: Load Messages ---
  Future<void> _loadFromDevice({bool silent = false}) async {
    if (!silent) state = SmsState(sosList: state.sosList, otherList: state.otherList, isLoading: true);

    try {
      final rawMessages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final sos = <RescueMessage>[];
      final other = <RescueMessage>[];
      final prefixes = ['sos', 'cuu', 'help'];

      // Optimize: Take 100
      for (var sms in rawMessages.take(AppConstants.smsLoadLimit)) {
        final body = (sms.body ?? "").toLowerCase();
        final phone = AppUtils.formatPhoneNumber(sms.address ?? "Unknown");
        final date = sms.date ?? 0;

        // DB Check for Override
        final record = await DatabaseHelper.instance.getRecord(phone, date);
        
        bool isSos = prefixes.any((p) => body.startsWith(p));
        ExtractedInfo info = ExtractedInfo();

        if (record != null) {
          info = ExtractedInfo.fromJson(record);
          if (record['is_sos'] != null) isSos = record['is_sos'] == 1;
        }

        final msg = RescueMessage(
          originalMessage: sms,
          sender: phone,
          info: info,
          isSos: isSos,
        );

        if (isSos) sos.add(msg); else other.add(msg);
      }

      state = SmsState(sosList: sos, otherList: other, isLoading: false);
      
      // Auto-Queue
      for (var m in sos) {
        if (!m.info.isAnalyzed) _addToQueue(m);
      }

    } catch (e) {
      if (!silent) state = SmsState(isLoading: false);
    }
  }

  // --- CORE: Incoming SMS ---
  void _handleIncoming(SmsMessage m) {
    final phone = AppUtils.formatPhoneNumber(m.address ?? "Unknown");
    final body = (m.body ?? "").toLowerCase();
    
    // Dupe Check
    final exists = state.sosList.any((x) => x.originalMessage.date == m.date) || 
                   state.otherList.any((x) => x.originalMessage.date == m.date);
    if (exists) return;

    final prefixes = ['sos', 'cuu', 'help'];
    final isSos = prefixes.any((p) => body.startsWith(p));

    final msg = RescueMessage(
      originalMessage: m,
      sender: phone,
      info: ExtractedInfo(),
      isSos: isSos,
    );

    if (isSos) {
      state = SmsState(sosList: [msg, ...state.sosList], otherList: state.otherList, isLoading: false);
      _addToQueue(msg);
    } else {
      state = SmsState(sosList: state.sosList, otherList: [msg, ...state.otherList], isLoading: false);
    }
  }

  // --- CORE: Queue ---
  void _addToQueue(RescueMessage msg) {
    if (!msg.isSos || msg.info.isAnalyzed || msg.isAnalyzing) return;
    // De-dupe Queue
    if (_queue.any((m) => m.originalMessage.date == msg.originalMessage.date)) return;
    
    _queue.add(msg);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isQueueRunning) return;
    _isQueueRunning = true;

    while (_queue.isNotEmpty) {
      var msg = _queue.first;
      
      // UI: Analyzing
      _updateLocalMessage(msg.copyWith(isAnalyzing: true));

      final settings = ref.read(settingsProvider);
      
      // AI Call
      final result = await GeminiService().analyze(
        msg.originalMessage.body ?? "", 
        msg.sender, 
        settings.apiKey
      );

      // Backoff if Rate Limit
      if (result.needsRetry) {
        await Future.delayed(const Duration(seconds: 20));
        continue; 
      }

      // Save to DB
      if (result.isAnalyzed) {
        await DatabaseHelper.instance.saveState(
          msg.sender, msg.originalMessage.date ?? 0, result, msg.isSos
        );
      }

      // Update Msg
      msg = msg.copyWith(info: result, isAnalyzing: false);
      _updateLocalMessage(msg);
      _queue.removeAt(0);

      // Auto Send
      if (settings.autoSend && result.isAnalyzed && !msg.apiSent) {
        await sendAlert(msg);
      }

      await Future.delayed(const Duration(seconds: 5));
    }
    _isQueueRunning = false;
  }

  // --- HELPERS ---
  void _updateLocalMessage(RescueMessage updated) {
    // Helper to update a single message in the list without full reload
    if (updated.isSos) {
      final list = state.sosList.map((m) => m.originalMessage.date == updated.originalMessage.date ? updated : m).toList();
      state = SmsState(sosList: list, otherList: state.otherList, isLoading: false);
    }
  }

  // Actions
  Future<void> moveMessage(RescueMessage msg, bool toSos) async {
    final updated = msg.copyWith(isSos: toSos);
    await DatabaseHelper.instance.saveState(msg.sender, msg.originalMessage.date ?? 0, msg.info, toSos);
    // Reload lists to reflect change
    _loadFromDevice(silent: true);
  }

  Future<bool> sendAlert(RescueMessage msg) async {
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(); } catch (_) {}
    
    final success = await RescueApiService().sendRequest(msg.info, pos);
    if (success) {
      _updateLocalMessage(msg.copyWith(apiSent: true));
    }
    return success;
  }

  // Called manually after editing form
  Future<void> updateAndSave(RescueMessage msg, ExtractedInfo newInfo) async {
    final updated = msg.copyWith(info: newInfo);
    await DatabaseHelper.instance.saveState(msg.sender, msg.originalMessage.date ?? 0, newInfo, msg.isSos);
    _updateLocalMessage(updated);
  }

  // Called from Config Tab
  int retryFailed() {
    int c = 0;
    for (var m in state.sosList) {
      if (!m.info.isAnalyzed) { _addToQueue(m); c++; }
    }
    return c;
  }
}

final smsProvider = StateNotifierProvider<SmsNotifier, SmsState>((ref) => SmsNotifier(ref));