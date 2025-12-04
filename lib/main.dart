import 'dart:async';
import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

// Imports
import 'core/constants.dart';
import 'data/local/db_helper.dart';
import 'data/local/prefs_helper.dart'; // Import Prefs
import 'data/remote/gemini_service.dart';
import 'data/remote/rescue_api_service.dart';
import 'data/models/rescue_message.dart';
import 'data/models/extracted_info.dart';
import 'ui/screens/sms_tab.dart';
import 'ui/screens/webview_tab.dart';
import 'ui/screens/config_tab.dart'; // Import Config Tab

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: HomeScreen(),
  ));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final Telephony telephony = Telephony.instance;
  
  List<RescueMessage> sosMessages = [];
  List<RescueMessage> otherMessages = [];
  bool isLoading = true;

  List<RescueMessage> _processingQueue = [];
  bool _isProcessorRunning = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) { _loadMessages(); },
      onBackgroundMessage: backgroundHandler 
    );
  }

  static void backgroundHandler(SmsMessage message) {}

  // --- LOGIC: PROCESS QUEUE ---
  void _addToAnalysisQueue(RescueMessage msg) {
    if (!msg.isSos || msg.info.isAnalyzed || msg.isAnalyzing) return;
    if (!_processingQueue.contains(msg)) {
      _processingQueue.add(msg);
      _runQueueProcessor();
    }
  }

  void _runQueueProcessor() async {
    if (_isProcessorRunning) return;
    _isProcessorRunning = true;

    while (_processingQueue.isNotEmpty) {
      final msg = _processingQueue.first;
      if (mounted) setState(() => msg.isAnalyzing = true);

      // Call Service (Now uses Key from Prefs)
      final result = await GeminiService.extractData(
        msg.originalMessage.body ?? "", 
        msg.originalMessage.address ?? "Unknown"
      );

      if (result.needsRetry) {
        await Future.delayed(const Duration(seconds: 20));
        continue;
      }

      // Save to DB
      if (result.isAnalyzed) {
         await DatabaseHelper.instance.cacheAnalysis(
           msg.originalMessage.address ?? "Unknown", 
           msg.originalMessage.date ?? 0, 
           result
         );
      }

      // Update Local State
      if (mounted) setState(() { msg.info = result; msg.isAnalyzing = false; });
      _processingQueue.removeAt(0);

      // -------------------------------------------------------------
      // AUTO SEND LOGIC
      // -------------------------------------------------------------
      // Check if Auto Send is ON and we haven't sent this message yet
      bool autoSendEnabled = await PrefsHelper.getAutoSend();
      if (autoSendEnabled && result.isAnalyzed && !msg.apiSent) {
        debugPrint("🤖 Auto-sending message...");
        await _performSend(msg); // Send immediately
      }

      await Future.delayed(const Duration(seconds: 5));
    }
    _isProcessorRunning = false;
  }

  // --- LOGIC: LOAD MESSAGES ---
  Future<void> _loadMessages() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    await [Permission.sms, Permission.location].request();

    List<SmsMessage> rawMessages = await telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );

    List<RescueMessage> tempSos = [];
    List<RescueMessage> tempOther = [];
    List<String> prefixes = ['sos', 'cuu', 'help'];
    int otherCount = 0;

    for (var sms in rawMessages) {
      String body = (sms.body ?? "").toLowerCase();
      bool isSos = prefixes.any((prefix) => body.startsWith(prefix));
      
      ExtractedInfo cachedInfo = ExtractedInfo();
      if (isSos) {
        final dbResult = await DatabaseHelper.instance.getCachedAnalysis(sms.address ?? "Unknown", sms.date ?? 0);
        if (dbResult != null) cachedInfo = dbResult;
      }

      var msgObj = RescueMessage(originalMessage: sms, info: cachedInfo, isSos: isSos);

      if (isSos) tempSos.add(msgObj);
      else if (otherCount < 50) { tempOther.add(msgObj); otherCount++; }
    }

    if (mounted) {
      setState(() {
        sosMessages = tempSos;
        otherMessages = tempOther;
        isLoading = false;
      });
      for (var msg in sosMessages) {
        if (!msg.info.isAnalyzed) _addToAnalysisQueue(msg);
      }
    }
  }

  void _moveMessage(RescueMessage message, bool targetIsSos) {
    setState(() {
      message.isSos = targetIsSos;
      if (targetIsSos) {
        otherMessages.remove(message);
        sosMessages.insert(0, message);
        _addToAnalysisQueue(message);
      } else {
        sosMessages.remove(message);
        otherMessages.insert(0, message);
      }
    });
  }

  // --- REFACTORED SEND LOGIC (Used by both Manual and Auto) ---
  Future<void> _performSend(RescueMessage msg) async {
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(); } catch (_) {}

    try {
      bool success = await RescueApiService.sendRequest(msg.info, pos);
      if (success) {
        if(mounted) setState(() => msg.apiSent = true);
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Sent!")));
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Failed to send")));
      }
    } catch (e) {
      debugPrint("Send Error: $e");
    }
  }

  Future<void> _handleManualSend(RescueMessage msg) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirm Send"),
        content: const Text("Send this SOS request to the Rescue Map?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Confirm")),
        ],
      ),
    ) ?? false;

    if (!confirm) return;
    
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sending...")));
    await _performSend(msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const WebViewTab(),
          SmsTab(
            sosList: sosMessages, 
            otherList: otherMessages, 
            isLoading: isLoading, 
            onMove: _moveMessage, 
            onManualSend: _handleManualSend
          ),
          const ConfigTab(), // NEW TAB
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: "Map"),
          NavigationDestination(icon: Icon(Icons.mark_chat_unread), label: "Inbox"),
          NavigationDestination(icon: Icon(Icons.settings), label: "Config"), // NEW ICON
        ],
      ),
    );
  }
}