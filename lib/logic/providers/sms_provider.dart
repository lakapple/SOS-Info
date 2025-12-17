import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../data/local/db_helper.dart';
import '../../data/models/rescue_message.dart';
import '../../data/models/extracted_info.dart';
import '../../data/models/request_type.dart';
import 'queue_provider.dart';

class SmsState {
  final List<RescueMessage> sosList;
  final List<RescueMessage> otherList;
  final bool isLoading;
  SmsState({this.sosList = const [], this.otherList = const [], this.isLoading = true});
}

class SmsNotifier extends StateNotifier<SmsState> {
  final Ref ref;
  final Telephony _telephony = Telephony.instance;
  Timer? _pollingTimer;

  SmsNotifier(this.ref) : super(SmsState()) {
    ref.onDispose(() => _pollingTimer?.cancel());
  }

  static void bgHandler(SmsMessage m) {}

  Future<void> init() async {
    final status = await [Permission.sms, Permission.location].request();
    if (status[Permission.sms] != PermissionStatus.granted) {
      state = SmsState(isLoading: false);
      return;
    }

    _telephony.listenIncomingSms(
      onNewMessage: (m) => _handleIncoming(m),
      onBackgroundMessage: bgHandler
    );

    await _loadFromDevice();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) => _loadFromDevice(silent: true));
  }

  // --- TEMPLATE PARSER ---
  ExtractedInfo? _parseTemplate(String body, String sender) {
    if (!body.toLowerCase().startsWith("sostemplate")) return null;
    try {
      final parts = body.split(':');
      if (parts.length < 7) return null;
      
      // 0:sostemplate 1:phones 2:type 3:people 4:address 5:lat-long 6:content
      final phones = parts[1].trim().split(',').map((e) => e.trim()).toList();
      final typeStr = parts[2].trim();
      final people = int.tryParse(parts[3].trim()) ?? 1;
      final address = parts[4].trim();
      
      final locParts = parts[5].trim().split('-');
      double lat = 0.0, lng = 0.0;
      if (locParts.length == 2) {
        lat = double.tryParse(locParts[0]) ?? 0.0;
        lng = double.tryParse(locParts[1]) ?? 0.0;
      }
      
      final content = parts.sublist(6).join(':').trim();
      RequestType type = RequestType.CUSTOM;
      for (var t in RequestType.values) if (t.name == typeStr) type = t;

      return ExtractedInfo(
        phoneNumbers: phones.isEmpty ? [sender] : phones,
        content: content,
        peopleCount: people,
        address: address,
        lat: lat, lng: lng,
        requestType: type,
        isAnalyzed: true
      );
    } catch (e) {
      debugPrint("Template Error: $e");
      return null;
    }
  }

  // --- HANDLING ---
  void _handleIncoming(SmsMessage m) {
    final phone = AppUtils.formatPhoneNumber(m.address ?? "Unknown");
    final body = (m.body ?? "").toLowerCase();
    
    // De-dupe based on timestamp
    if (state.sosList.any((x) => x.originalMessage.date == m.date) || 
        state.otherList.any((x) => x.originalMessage.date == m.date)) return;

    final prefixes = ['sos', 'cuu', 'help', 'sostemplate'];
    bool isSos = prefixes.any((p) => body.startsWith(p));
    
    ExtractedInfo info = ExtractedInfo();
    bool parsed = false;

    // Check Template
    final templateInfo = _parseTemplate(m.body ?? "", phone);
    if (templateInfo != null) {
      info = templateInfo;
      parsed = true;
    }

    final msg = RescueMessage(
      originalMessage: m,
      sender: phone,
      info: info,
      isSos: isSos,
    );

    if (isSos) {
      state = SmsState(sosList: [msg, ...state.sosList], otherList: state.otherList, isLoading: false);
      
      if (parsed) {
        DatabaseHelper.instance.saveState(phone, m.date ?? 0, info, true);
      } else {
        ref.read(queueProvider.notifier).addToQueue(msg);
      }
    } else {
      state = SmsState(sosList: state.sosList, otherList: [msg, ...state.otherList], isLoading: false);
    }
  }

  Future<void> _loadFromDevice({bool silent = false}) async {
    if (!silent) state = SmsState(sosList: state.sosList, otherList: state.otherList, isLoading: true);

    try {
      final messages = await _telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      );

      final sos = <RescueMessage>[];
      final other = <RescueMessage>[];
      final prefixes = ['sos', 'cuu', 'help', 'sostemplate'];

      for (var sms in messages.take(AppConstants.smsLoadLimit)) {
        final body = (sms.body ?? "").toLowerCase();
        final phone = AppUtils.formatPhoneNumber(sms.address ?? "Unknown");
        final date = sms.date ?? 0;

        final record = await DatabaseHelper.instance.getRecord(phone, date);
        
        bool isSos = prefixes.any((p) => body.startsWith(p));
        ExtractedInfo info = ExtractedInfo();

        if (record != null) {
          info = ExtractedInfo.fromJson(record);
          if (record['is_sos'] != null) isSos = record['is_sos'] == 1;
        } else {
          // Check missed templates
          final templateInfo = _parseTemplate(sms.body ?? "", phone);
          if (templateInfo != null) info = templateInfo;
        }

        final msg = RescueMessage(
          originalMessage: sms, sender: phone, info: info, isSos: isSos
        );

        if (isSos) sos.add(msg); else other.add(msg);
      }

      state = SmsState(sosList: sos, otherList: other, isLoading: false);
      
      // Queue Unanalyzed
      for (var m in sos) {
        if (!m.info.isAnalyzed) ref.read(queueProvider.notifier).addToQueue(m);
      }

    } catch (e) {
      if (!silent) state = SmsState(isLoading: false);
    }
  }

  // --- ACTIONS ---
  Future<void> moveMessage(RescueMessage msg, bool toSos) async {
    await DatabaseHelper.instance.saveState(msg.sender, msg.originalMessage.date ?? 0, msg.info, toSos);
    _loadFromDevice(silent: true);
  }

  Future<void> updateAndSave(RescueMessage msg, ExtractedInfo newInfo) async {
    final updated = msg.copyWith(info: newInfo, isAnalyzing: false, hasManualOverride: true);
    await DatabaseHelper.instance.saveState(msg.sender, msg.originalMessage.date ?? 0, newInfo, msg.isSos);
    _updateList(updated);
  }

  void updateLocalInfo(RescueMessage msg, ExtractedInfo info) {
    final updated = msg.copyWith(info: info, isAnalyzing: false);
    _updateList(updated);
  }

  void updateLocalStatus(RescueMessage msg, {bool? apiSent, bool? isAnalyzing}) {
    var updated = msg;
    if (apiSent != null) updated = updated.copyWith(apiSent: apiSent);
    if (isAnalyzing != null) updated = updated.copyWith(isAnalyzing: isAnalyzing);
    _updateList(updated);
  }

  void _updateList(RescueMessage updated) {
    if (updated.isSos) {
      final list = state.sosList.map((m) => m.originalMessage.date == updated.originalMessage.date ? updated : m).toList();
      state = SmsState(sosList: list, otherList: state.otherList, isLoading: false);
    }
  }

  int retryFailed() {
    int c = 0;
    for (var m in state.sosList) {
      if (!m.info.isAnalyzed && !m.hasManualOverride) { 
        ref.read(queueProvider.notifier).addToQueue(m); 
        c++; 
      }
    }
    return c;
  }
}

final smsProvider = StateNotifierProvider<SmsNotifier, SmsState>((ref) => SmsNotifier(ref));