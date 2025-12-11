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

// ---------------------------------------------------------
// STATE CLASS
// ---------------------------------------------------------
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

// ---------------------------------------------------------
// NOTIFIER (LOGIC)
// ---------------------------------------------------------
class RescueNotifier extends StateNotifier<RescueState> {
  final Ref ref;
  final Telephony telephony = Telephony.instance;
  final List<RescueMessage> _processingQueue = [];
  Timer? _pollingTimer; // NEW: Backup Timer

  RescueNotifier(this.ref) : super(RescueState()) {
    // Clean up timer when provider is destroyed
    ref.onDispose(() {
      _pollingTimer?.cancel();
    });
  }

  @pragma('vm:entry-point')
  static void backgroundHandler(SmsMessage message) {}

  // 1. INITIALIZE
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

    // A. SETUP REAL-TIME LISTENER
    try {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) { 
          debugPrint("⚡ Real-time SMS: ${message.body}");
          _handleIncomingSms(message);
        },
        onBackgroundMessage: backgroundHandler
      );
    } catch (e) {
      debugPrint("Listener Error: $e");
    }

    // B. INITIAL LOAD
    await _loadMessages();

    // C. START POLLING (BACKUP MECHANISM)
    // Checks DB every 15 seconds in case Listener fails
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      _loadMessages(silent: true);
    });
  }

  // 2. HANDLE NEW SMS (INSTANT MEMORY INSERT)
  void _handleIncomingSms(SmsMessage message) {
    final body = (message.body ?? "").toLowerCase();
    final rawAddress = message.address ?? "Unknown";
    final cleanSender = AppUtils.formatPhoneNumber(rawAddress);
    
    // Check duplicates before inserting (Important for Polling + Listener mix)
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

  // 3. LOAD MESSAGES FROM DB
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
        bool isSos = prefixes.any((prefix) => body.startsWith(prefix));
        
        // Optimize: Only check DB Cache if we don't have this message in memory OR it's a full reload
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

      // If silent reload (polling), only update if count changed or to refresh data
      state = state.copyWith(
        sosMessages: tempSos,
        otherMessages: tempOther,
        isLoading: false
      );

      // Auto-analyze found SOS messages
      for (var msg in tempSos) {
        if (!msg.info.isAnalyzed) addToAnalysisQueue(msg);
      }

    } catch (e) {
      debugPrint("Error loading: $e");
      if (!silent) state = state.copyWith(isLoading: false);
    }
  }

  // 4. QUEUE LOGIC
  void addToAnalysisQueue(RescueMessage msg) {
    if (!msg.isSos || msg.info.isAnalyzed || msg.isAnalyzing) return;
    
    // Check duplication in queue
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
      
      // Update UI state
      msg.isAnalyzing = true; 
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
           msg.originalMessage.date ?? DateTime.now().millisecondsSinceEpoch, 
           result
         );
      }

      _processingQueue.removeAt(0);
      
      msg.info = result;
      msg.isAnalyzing = false;
      state = state.copyWith(); // Refresh UI

      // 2. Auto Send Check
      final settings = ref.read(settingsProvider);
      if (settings.autoSend && result.isAnalyzed && !msg.apiSent) {
        await performSend(msg);
      }

      await Future.delayed(const Duration(seconds: 5));
    }
    
    state = state.copyWith(isQueueRunning: false);
  }

  // 5. MANUAL ACTIONS
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

  void moveMessage(RescueMessage message, bool targetIsSos) {
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
      state = state.copyWith();
    }
    return success;
  }

  void updateMessageInfo(RescueMessage msg, ExtractedInfo newInfo) async {
    msg.info = newInfo;
    await DatabaseHelper.instance.cacheAnalysis(
       msg.sender, 
       msg.originalMessage.date ?? DateTime.now().millisecondsSinceEpoch, 
       newInfo
    );
    state = state.copyWith(); 
  }
}

// ---------------------------------------------------------
// PROVIDER
// ---------------------------------------------------------
final rescueProvider = StateNotifierProvider<RescueNotifier, RescueState>((ref) {
  return RescueNotifier(ref);
});