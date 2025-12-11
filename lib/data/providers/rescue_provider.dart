import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:telephony/telephony.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils.dart';
import '../local/db_helper.dart';
import '../remote/gemini_service.dart';
import '../remote/rescue_api_service.dart';
import '../models/rescue_message.dart';
import '../models/extracted_info.dart';
import 'settings_provider.dart';

// State Class (Unchanged)
class RescueState {
  final List<RescueMessage> sosMessages;
  final List<RescueMessage> otherMessages;
  final bool isLoading;
  final bool isQueueRunning;

  RescueState({
    this.sosMessages = const [],
    this.otherMessages = const [],
    this.isLoading = false,
    this.isQueueRunning = false,
  });

  RescueState copyWith({
    List<RescueMessage>? sosMessages,
    List<RescueMessage>? otherMessages,
    bool? isLoading,
    bool? isQueueRunning,
  }) {
    return RescueState(
      sosMessages: sosMessages ?? this.sosMessages,
      otherMessages: otherMessages ?? this.otherMessages,
      isLoading: isLoading ?? this.isLoading,
      isQueueRunning: isQueueRunning ?? this.isQueueRunning,
    );
  }
}

// Notifier
class RescueNotifier extends StateNotifier<RescueState> {
  final Ref ref;
  final Telephony telephony = Telephony.instance;
  final List<RescueMessage> _processingQueue = [];
  Timer? _pollingTimer;

  RescueNotifier(this.ref) : super(RescueState()) {
    ref.onDispose(() => _pollingTimer?.cancel());
  }

  @pragma('vm:entry-point')
  static void backgroundHandler(SmsMessage message) {}

  Future<void> initPermissionsAndListeners() async {
    state = state.copyWith(isLoading: true);
    await [Permission.sms, Permission.location].request();
    
    try {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) { 
          _handleIncomingSms(message);
        },
        onBackgroundMessage: backgroundHandler
      );
    } catch (e) {
      debugPrint("Listener Error: $e");
    }

    await _loadMessages();
    
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (t) => _loadMessages(silent: true));
  }

  void _handleIncomingSms(SmsMessage message) {
    final body = (message.body ?? "").toLowerCase();
    final rawAddress = message.address ?? "Unknown";
    final cleanSender = AppUtils.formatPhoneNumber(rawAddress);
    
    bool exists = state.sosMessages.any((m) => m.originalMessage.date == message.date) || 
                  state.otherMessages.any((m) => m.originalMessage.date == message.date);
    if (exists) return;

    List<String> prefixes = ['sos', 'cuu', 'help'];
    bool isSos = prefixes.any((prefix) => body.startsWith(prefix));

    final newMessage = RescueMessage(
      originalMessage: message,
      sender: cleanSender,
      info: ExtractedInfo(),
      isSos: isSos
    );

    if (isSos) {
      state = state.copyWith(sosMessages: [newMessage, ...state.sosMessages]);
      addToAnalysisQueue(newMessage);
    } else {
      state = state.copyWith(otherMessages: [newMessage, ...state.otherMessages]);
    }
  }

  // --- LOAD MESSAGES (UPDATED) ---
  Future<void> _loadMessages({bool silent = false}) async {
    try {
      if (!silent) state = state.copyWith(isLoading: true);

      List<SmsMessage> rawMessages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      ).timeout(const Duration(seconds: 10), onTimeout: () => []);

      List<RescueMessage> tempSos = [];
      List<RescueMessage> tempOther = [];
      List<String> prefixes = ['sos', 'cuu', 'help'];
      int otherCount = 0;

      for (var sms in rawMessages) {
        String body = (sms.body ?? "").toLowerCase();
        String rawAddress = sms.address ?? "Unknown";
        String cleanSender = AppUtils.formatPhoneNumber(rawAddress);
        
        // 1. Determine Default Status based on Prefix
        bool isSos = prefixes.any((prefix) => body.startsWith(prefix));
        
        // 2. Check Database for Override & Info
        ExtractedInfo cachedInfo = ExtractedInfo();
        
        final dbData = await DatabaseHelper.instance.getCachedData(cleanSender, sms.date ?? 0);
        
        if (dbData != null) {
          // Recover ExtractedInfo
          cachedInfo = ExtractedInfo.fromJson(dbData);
          
          // RECOVER SOS STATUS (The Fix)
          // If 'is_sos' column exists and is not null, respect it.
          if (dbData['is_sos'] != null) {
            isSos = dbData['is_sos'] == 1;
          }
        }

        var msgObj = RescueMessage(
          originalMessage: sms,
          sender: cleanSender,
          info: cachedInfo, 
          isSos: isSos
        );

        if (isSos) {
          tempSos.add(msgObj);
        } else if (otherCount < 50) { 
          tempOther.add(msgObj); 
          otherCount++; 
        }
      }

      state = state.copyWith(
        sosMessages: tempSos,
        otherMessages: tempOther,
        isLoading: false
      );

      for (var msg in tempSos) {
        if (!msg.info.isAnalyzed) addToAnalysisQueue(msg);
      }

    } catch (e) {
      if (!silent) state = state.copyWith(isLoading: false);
    }
  }

  void addToAnalysisQueue(RescueMessage msg) {
    if (!msg.isSos || msg.info.isAnalyzed || msg.isAnalyzing) return;
    bool alreadyQueued = _processingQueue.any((m) => 
        m.originalMessage.date == msg.originalMessage.date && m.sender == msg.sender
    );
    if (!alreadyQueued) {
      _processingQueue.add(msg);
      _runQueueProcessor();
    }
  }

  void _runQueueProcessor() async {
    if (state.isQueueRunning) return;
    state = state.copyWith(isQueueRunning: true);

    while (_processingQueue.isNotEmpty) {
      final msg = _processingQueue.first;
      
      msg.isAnalyzing = true; 
      state = state.copyWith(); 

      final result = await GeminiService.extractData(msg.originalMessage.body ?? "", msg.sender);

      if (result.needsRetry) {
        await Future.delayed(const Duration(seconds: 20));
        continue; 
      }

      if (result.isAnalyzed) {
         // SAVE: Info + Status (true because it's in queue means it is SOS)
         await DatabaseHelper.instance.saveMessageState(
           msg.sender, 
           msg.originalMessage.date ?? 0, 
           result,
           true // isSos
         );
      }

      _processingQueue.removeAt(0);
      msg.info = result;
      msg.isAnalyzing = false;
      state = state.copyWith(); 

      final settings = ref.read(settingsProvider);
      if (settings.autoSend && result.isAnalyzed && !msg.apiSent) {
        await performSend(msg);
      }

      await Future.delayed(const Duration(seconds: 5));
    }
    
    state = state.copyWith(isQueueRunning: false);
  }

  int triggerPendingAnalysis() {
    int count = 0;
    for (var msg in state.sosMessages) {
      if (!msg.info.isAnalyzed || msg.info.content.startsWith("Error")) {
        addToAnalysisQueue(msg);
        count++;
      }
    }
    return count;
  }

  // --- MANUAL ACTIONS (UPDATED) ---
  void moveMessage(RescueMessage message, bool targetIsSos) async {
    List<RescueMessage> newSos = List.from(state.sosMessages);
    List<RescueMessage> newOther = List.from(state.otherMessages);

    message.isSos = targetIsSos;

    if (targetIsSos) {
      newOther.remove(message);
      newSos.insert(0, message);
      addToAnalysisQueue(message);
    } else {
      newSos.remove(message);
      newOther.insert(0, message);
    }

    state = state.copyWith(sosMessages: newSos, otherMessages: newOther);

    // FIX: PERSIST THE MOVE TO DATABASE IMMEDIATELY
    await DatabaseHelper.instance.saveMessageState(
      message.sender, 
      message.originalMessage.date ?? 0, 
      message.info, // Save existing info (even if empty)
      targetIsSos   // Save the new status
    );
  }

  Future<bool> performSend(RescueMessage msg) async {
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(); } catch (_) {}
    
    bool success = await RescueApiService.sendRequest(msg.info, pos);
    
    if (success) {
      msg.apiSent = true;
      state = state.copyWith();
    }
    return success;
  }

  void updateMessageInfo(RescueMessage msg, ExtractedInfo newInfo) async {
    msg.info = newInfo;
    await DatabaseHelper.instance.saveMessageState(
       msg.sender, 
       msg.originalMessage.date ?? 0, 
       newInfo,
       msg.isSos // Keep current status
    );
    state = state.copyWith(); 
  }
}

final rescueProvider = StateNotifierProvider<RescueNotifier, RescueState>((ref) {
  return RescueNotifier(ref);
});