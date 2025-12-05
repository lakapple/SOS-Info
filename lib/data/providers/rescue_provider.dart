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

// State Class
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

  RescueNotifier(this.ref) : super(RescueState()) {
    // We don't auto-init here to allow UI to show permissions dialog first
  }

  static void backgroundHandler(SmsMessage message) {}

  // 1. INITIALIZE & PERMISSIONS
  Future<void> initPermissionsAndListeners() async {
    state = state.copyWith(isLoading: true);
    
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.location,
    ].request();

    if (statuses[Permission.sms] != PermissionStatus.granted) {
      state = state.copyWith(isLoading: false);
      return;
    }

    try {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) { _loadMessages(); },
        onBackgroundMessage: backgroundHandler
      );
    } catch (e) {
      debugPrint("Listener Error: $e");
    }

    await _loadMessages();
  }

  // 2. LOAD MESSAGES
  Future<void> _loadMessages() async {
    try {
      state = state.copyWith(isLoading: true);

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
        bool isSos = prefixes.any((prefix) => body.startsWith(prefix));
        
        ExtractedInfo cachedInfo = ExtractedInfo();
        if (isSos) {
          final dbResult = await DatabaseHelper.instance.getCachedAnalysis(cleanSender, sms.date ?? 0);
          if (dbResult != null) cachedInfo = dbResult;
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

      // Trigger Queue for unanalyzed SOS messages
      for (var msg in tempSos) {
        if (!msg.info.isAnalyzed) addToAnalysisQueue(msg);
      }

    } catch (e) {
      debugPrint("Error loading: $e");
      state = state.copyWith(isLoading: false);
    }
  }

  // 3. QUEUE LOGIC
  void addToAnalysisQueue(RescueMessage msg) {
    if (!msg.isSos || msg.info.isAnalyzed || msg.isAnalyzing) return;
    if (!_processingQueue.contains(msg)) {
      _processingQueue.add(msg);
      _runQueueProcessor();
    }
  }

  void _runQueueProcessor() async {
    if (state.isQueueRunning) return;
    state = state.copyWith(isQueueRunning: true);

    while (_processingQueue.isNotEmpty) {
      final msg = _processingQueue.first;
      
      // Update UI: Message is analyzing
      msg.isAnalyzing = true; 
      // Force UI refresh (Riverpod doesn't detect deep object changes automatically without immutability)
      state = state.copyWith(); 

      // 1. AI Extract
      final result = await GeminiService.extractData(
        msg.originalMessage.body ?? "", 
        msg.sender 
      );

      if (result.needsRetry) {
        await Future.delayed(const Duration(seconds: 20));
        continue; 
      }

      if (result.isAnalyzed) {
         await DatabaseHelper.instance.cacheAnalysis(
           msg.sender, 
           msg.originalMessage.date ?? 0, 
           result
         );
      }

      _processingQueue.removeAt(0);
      
      // Update Message Info
      msg.info = result;
      msg.isAnalyzing = false;
      state = state.copyWith(); // Refresh UI

      // 2. Auto Send Check
      final settings = ref.read(settingsProvider); // Access settings via Ref
      if (settings.autoSend && result.isAnalyzed && !msg.apiSent) {
        await performSend(msg);
      }

      await Future.delayed(const Duration(seconds: 5));
    }
    
    state = state.copyWith(isQueueRunning: false);
  }

  // 4. TRIGGER ALL PENDING (From Config)
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

  // 5. MANUAL ACTIONS
  void moveMessage(RescueMessage message, bool targetIsSos) {
    // We need to create new lists to trigger Riverpod state update
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
  }

  Future<bool> performSend(RescueMessage msg) async {
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(); } catch (_) {}
    
    bool success = await RescueApiService.sendRequest(msg.info, pos);
    
    if (success) {
      msg.apiSent = true;
      state = state.copyWith(); // Update UI icon
    }
    return success;
  }

  void updateMessageInfo(RescueMessage msg, ExtractedInfo newInfo) async {
    msg.info = newInfo;
    // Cache the edit
    await DatabaseHelper.instance.cacheAnalysis(
       msg.sender, 
       msg.originalMessage.date ?? 0, 
       newInfo
    );
    state = state.copyWith(); // Refresh UI
  }
}

// Provider Definition
final rescueProvider = StateNotifierProvider<RescueNotifier, RescueState>((ref) {
  return RescueNotifier(ref);
});