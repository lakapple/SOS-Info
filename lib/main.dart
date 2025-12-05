import 'dart:async';
import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import 'core/constants.dart';
import 'data/local/db_helper.dart';
import 'data/local/prefs_helper.dart';
import 'data/remote/gemini_service.dart';
import 'data/remote/rescue_api_service.dart';
import 'data/models/rescue_message.dart';
import 'data/models/extracted_info.dart';
import 'data/models/request_type.dart';
import 'ui/screens/sms_tab.dart';
import 'ui/screens/webview_tab.dart';
import 'ui/screens/config_tab.dart';

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
  bool isLoading = true; // Start true

  List<RescueMessage> _processingQueue = [];
  bool _isProcessorRunning = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure context is ready for Dialogs/Permissions
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialSetup();
    });
  }

  static void backgroundHandler(SmsMessage message) {}

  // --- 1. ROBUST INITIALIZATION ---
  Future<void> _initialSetup() async {
    setState(() => isLoading = true);

    // Request Permissions Sequentially
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.location,
    ].request();

    if (statuses[Permission.sms] != PermissionStatus.granted) {
      if (mounted) {
        setState(() => isLoading = false);
        _showPermissionError();
      }
      return;
    }

    // Permissions OK -> Init Listener & Load Data
    _initSmsListener();
    await _loadMessages();
  }

  void _showPermissionError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("SMS Permission Required. Please enable in Settings."),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 5),
      ),
    );
  }

  void _initSmsListener() {
    try {
      telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) { _loadMessages(); },
        onBackgroundMessage: backgroundHandler
      );
    } catch (e) {
      debugPrint("Listener Error: $e");
    }
  }

  // --- 2. LOAD MESSAGES (WITH TIMEOUT) ---
  Future<void> _loadMessages() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
      // TIMEOUT FIX: If getInboxSms takes > 10s, throw error so app doesn't freeze
      List<SmsMessage> rawMessages = await telephony.getInboxSms(
        columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
        sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
      ).timeout(const Duration(seconds: 10), onTimeout: () {
        debugPrint("⚠️ SMS Load Timeout");
        return [];
      });

      List<RescueMessage> tempSos = [];
      List<RescueMessage> tempOther = [];
      List<String> prefixes = ['sos', 'cuu', 'help'];
      int otherCount = 0;

      for (var sms in rawMessages) {
        String body = (sms.body ?? "").toLowerCase();
        bool isSos = prefixes.any((prefix) => body.startsWith(prefix));
        
        ExtractedInfo cachedInfo = ExtractedInfo();
        if (isSos) {
          final dbResult = await DatabaseHelper.instance.getCachedAnalysis(
            sms.address ?? "Unknown", 
            sms.date ?? 0
          );
          if (dbResult != null) cachedInfo = dbResult;
        }

        var msgObj = RescueMessage(originalMessage: sms, info: cachedInfo, isSos: isSos);

        if (isSos) {
          tempSos.add(msgObj);
        } else if (otherCount < 50) { 
          tempOther.add(msgObj); 
          otherCount++; 
        }
      }

      if (mounted) {
        setState(() {
          sosMessages = tempSos;
          otherMessages = tempOther;
          isLoading = false; // SUCCESS
        });
        
        // Trigger Queue
        for (var msg in sosMessages) {
          if (!msg.info.isAnalyzed) _addToAnalysisQueue(msg);
        }
      }

    } catch (e) {
      debugPrint("❌ Error loading messages: $e");
      if (mounted) {
        setState(() => isLoading = false); // FAILURE SAFETY
      }
    }
  }

  // --- 3. QUEUE SYSTEM ---
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

      final result = await GeminiService.extractData(
        msg.originalMessage.body ?? "", 
        msg.originalMessage.address ?? "Unknown"
      );

      if (result.needsRetry) {
        await Future.delayed(const Duration(seconds: 20));
        continue;
      }

      if (result.isAnalyzed) {
         await DatabaseHelper.instance.cacheAnalysis(
           msg.originalMessage.address ?? "Unknown", 
           msg.originalMessage.date ?? 0, 
           result
         );
      }

      _processingQueue.removeAt(0);
      if (mounted) setState(() { msg.info = result; msg.isAnalyzing = false; });

      bool autoSendEnabled = await PrefsHelper.getAutoSend();
      if (autoSendEnabled && result.isAnalyzed && !msg.apiSent) {
        await _performSend(msg);
      }

      await Future.delayed(const Duration(seconds: 5));
    }
    _isProcessorRunning = false;
  }

  // --- 4. ACTION LOGIC ---
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

  Future<void> _performSend(RescueMessage msg) async {
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(); } catch (_) {}
    
    bool success = await RescueApiService.sendRequest(msg.info, pos);
    if (success) {
      if(mounted) setState(() => msg.apiSent = true);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Sent!")));
    } else {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Failed to send")));
    }
  }

  Future<void> _handleManualSend(RescueMessage msg) async {
    ExtractedInfo? editedInfo = await _showEditDialog(context, msg);
    if (editedInfo == null) return; 

    setState(() => msg.info = editedInfo);
    
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sending...")));
    await _performSend(msg);
  }

  Future<ExtractedInfo?> _showEditDialog(BuildContext context, RescueMessage msg) async {
    final info = msg.info;
    TextEditingController phoneCtrl = TextEditingController(text: info.phoneNumbers.join(", "));
    TextEditingController peopleCtrl = TextEditingController(text: info.peopleCount.toString());
    TextEditingController addressCtrl = TextEditingController(text: info.address);
    TextEditingController contentCtrl = TextEditingController(text: info.content);
    RequestType selectedType = info.requestType;

    return showDialog<ExtractedInfo>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Confirm & Edit"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Phones (comma sep)")),
                     DropdownButtonFormField<RequestType>(
                        value: selectedType,
                        decoration: const InputDecoration(labelText: "Type"),
                        isExpanded: true,
                        items: RequestType.values.map((type) => DropdownMenuItem(value: type, child: Text(type.vietnameseName))).toList(),
                        onChanged: (val) { if(val != null) setDialogState(() => selectedType = val); },
                     ),
                     TextField(controller: peopleCtrl, decoration: const InputDecoration(labelText: "People Count"), keyboardType: TextInputType.number),
                     TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: "Address"), maxLines: 2),
                     TextField(controller: contentCtrl, decoration: const InputDecoration(labelText: "Help Content"), maxLines: 3),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text("Cancel")),
                FilledButton(
                  onPressed: () {
                    final newInfo = ExtractedInfo(
                      phoneNumbers: phoneCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                      content: contentCtrl.text,
                      peopleCount: int.tryParse(peopleCtrl.text) ?? 1,
                      address: addressCtrl.text,
                      requestType: selectedType,
                      isAnalyzed: true,
                    );
                    Navigator.pop(ctx, newInfo);
                  }, 
                  child: const Text("SEND NOW")
                ),
              ],
            );
          },
        );
      },
    );
  }

  // --- 5. UI BUILD ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const WebViewTab(),
          // Passing a manual refresh button to SmsTab in case lists are empty
          sosMessages.isEmpty && otherMessages.isEmpty && !isLoading
            ? Center(child: ElevatedButton(onPressed: _loadMessages, child: const Text("Retry Load SMS")))
            : SmsTab(sosList: sosMessages, otherList: otherMessages, isLoading: isLoading, onMove: _moveMessage, onManualSend: _handleManualSend),
          const ConfigTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: "Map"),
          NavigationDestination(icon: Icon(Icons.mark_chat_unread), label: "Inbox"),
          NavigationDestination(icon: Icon(Icons.settings), label: "Config"),
        ],
      ),
    );
  }
}