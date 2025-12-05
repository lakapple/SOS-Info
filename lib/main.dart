import 'dart:async';
import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

import 'core/utils.dart';
import 'core/constants.dart';
import 'data/local/db_helper.dart';
import 'data/local/prefs_helper.dart';
import 'data/remote/gemini_service.dart';
import 'data/remote/rescue_api_service.dart';
import 'data/models/rescue_message.dart';
import 'data/models/extracted_info.dart';
import 'data/models/request_type.dart';

// UI Screens
import 'ui/screens/sms_tab.dart';
import 'ui/screens/webview_tab.dart';
import 'ui/screens/config_tab.dart';

// ---------------------------------------------------------
// MAIN ENTRY POINT
// ---------------------------------------------------------
void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'SOS Rescue App',
    home: HomeScreen(),
  ));
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Navigation State
  int _currentIndex = 0;
  
  // SMS & Logic State
  final Telephony telephony = Telephony.instance;
  List<RescueMessage> sosMessages = [];
  List<RescueMessage> otherMessages = [];
  bool isLoading = true;

  // Analysis Queue
  List<RescueMessage> _processingQueue = [];
  bool _isProcessorRunning = false;

  @override
  void initState() {
    super.initState();
    // Safety: Run setup after the first frame to handle Dialog contexts if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialSetup();
    });
  }

  // Static handler for background execution (required by telephony)
  static void backgroundHandler(SmsMessage message) {}

  // ---------------------------------------------------------------------------
  // 1. INITIALIZATION & PERMISSIONS
  // ---------------------------------------------------------------------------
  Future<void> _initialSetup() async {
    setState(() => isLoading = true);

    // Request Permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.sms,
      Permission.location,
    ].request();

    if (statuses[Permission.sms] != PermissionStatus.granted) {
      if (mounted) {
        setState(() => isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("SMS Permission is required."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    _initSmsListener();
    await _loadMessages();
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

  // ---------------------------------------------------------------------------
  // 2. LOAD MESSAGES (WITH DB CACHE & TIMEOUT)
  // ---------------------------------------------------------------------------
  Future<void> _loadMessages() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    try {
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
        
        // --- STEP 1: SANITIZE NUMBER IMMEDIATELY ---
        String rawAddress = sms.address ?? "Unknown";
        String cleanSender = AppUtils.formatPhoneNumber(rawAddress); 

        bool isSos = prefixes.any((prefix) => body.startsWith(prefix));
        
        // --- STEP 2: USE CLEAN SENDER FOR DB CACHE ---
        ExtractedInfo cachedInfo = ExtractedInfo();
        if (isSos) {
          final dbResult = await DatabaseHelper.instance.getCachedAnalysis(
            cleanSender, // Use clean number for DB key
            sms.date ?? 0
          );
          if (dbResult != null) cachedInfo = dbResult;
        }

        var msgObj = RescueMessage(
          originalMessage: sms,
          sender: cleanSender, // Store sanitized number in model
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

    } catch (e) {
      debugPrint("Error loading messages: $e");
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 3. ANALYSIS QUEUE SYSTEM (GEMINI)
  // ---------------------------------------------------------------------------
  void _addToAnalysisQueue(RescueMessage msg) {
    if (!msg.isSos || msg.info.isAnalyzed || msg.isAnalyzing) return;
    
    // Avoid duplicates
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

      // Use msg.sender (already formatted)
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
           msg.sender, // Save to DB with formatted number
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

  // ---------------------------------------------------------------------------
  // 4. ACTIONS (SEND, MOVE, EDIT)
  // ---------------------------------------------------------------------------
  
  // Called by Config Tab "Save & Apply"
  void _triggerPendingAnalysis() {
    debugPrint("🔄 Triggering pending analysis...");
    int count = 0;
    for (var msg in sosMessages) {
      if (!msg.info.isAnalyzed || msg.info.content.startsWith("Error")) {
        _addToAnalysisQueue(msg);
        count++;
      }
    }
    if (count > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Queueing $count messages for analysis...")),
      );
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

  Future<void> _performSend(RescueMessage msg) async {
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(); } catch (_) {}
    
    bool success = await RescueApiService.sendRequest(msg.info, pos);
    
    if (mounted) {
      if (success) {
        setState(() => msg.apiSent = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Alert Sent Successfully!")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("⚠️ Failed to send alert.")),
        );
      }
    }
  }

  Future<void> _handleManualSend(RescueMessage msg) async {
    // Show Edit Dialog first
    ExtractedInfo? editedInfo = await _showEditDialog(context, msg);
    
    if (editedInfo == null) return; // User cancelled

    // Update with edited info
    setState(() => msg.info = editedInfo);
    
    // Save edited info to DB (Optional, but good practice)
    await DatabaseHelper.instance.cacheAnalysis(
       msg.originalMessage.address ?? "Unknown", 
       msg.originalMessage.date ?? 0, 
       editedInfo
    );

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sending...")));
    await _performSend(msg);
  }

  Future<ExtractedInfo?> _showEditDialog(BuildContext context, RescueMessage msg) async {
    final info = msg.info;
    
    // Controllers
    TextEditingController phoneCtrl = TextEditingController(text: info.phoneNumbers.join(", "));
    TextEditingController peopleCtrl = TextEditingController(text: info.peopleCount.toString());
    TextEditingController addressCtrl = TextEditingController(text: info.address);
    TextEditingController contentCtrl = TextEditingController(text: info.content);
    
    // Request Type State
    RequestType selectedType = info.requestType;

    return showDialog<ExtractedInfo>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Confirm & Edit"),
              // Reduce padding to maximize space
              contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              // Use constrained width/height to prevent layout thrashing
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  // physics: ClampingScrollPhysics is CRITICAL for keyboard performance
                  physics: const ClampingScrollPhysics(), 
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       // --- 1. REFERENCE MESSAGE (Added Top Section) ---
                       const Text(
                         "Reference Message (Long press to copy):", 
                         style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)
                       ),
                       const SizedBox(height: 4),
                       Container(
                         width: double.infinity,
                         constraints: const BoxConstraints(maxHeight: 120), // Limit height so form is visible
                         padding: const EdgeInsets.all(8),
                         decoration: BoxDecoration(
                           color: Colors.grey.shade100,
                           border: Border.all(color: Colors.grey.shade300),
                           borderRadius: BorderRadius.circular(4),
                         ),
                         child: SingleChildScrollView(
                           child: SelectableText(
                             msg.originalMessage.body ?? "",
                             style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.black87),
                           ),
                         ),
                       ),
                       const SizedBox(height: 15),
                       const Divider(),

                       // --- 2. FORM FIELDS ---
                       TextField(
                         controller: phoneCtrl, 
                         decoration: const InputDecoration(
                           labelText: "Phones (comma sep)", 
                           icon: Icon(Icons.phone, size: 20),
                           isDense: true, 
                           contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                         ),
                         keyboardType: TextInputType.phone,
                         style: const TextStyle(fontSize: 14),
                       ),
                       const SizedBox(height: 10),

                       DropdownButtonFormField<RequestType>(
                          value: selectedType,
                          decoration: const InputDecoration(
                            labelText: "Type", 
                            icon: Icon(Icons.category, size: 20),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          isExpanded: true,
                          items: RequestType.values.map((type) {
                            return DropdownMenuItem(
                              value: type, 
                              child: Text(type.vietnameseName, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)
                            );
                          }).toList(),
                          onChanged: (val) { if(val != null) setDialogState(() => selectedType = val); },
                       ),
                       const SizedBox(height: 10),

                       TextField(
                         controller: peopleCtrl, 
                         keyboardType: TextInputType.number,
                         decoration: const InputDecoration(
                           labelText: "People Count", 
                           icon: Icon(Icons.group, size: 20),
                           isDense: true,
                           contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                         ),
                         style: const TextStyle(fontSize: 14),
                       ),
                       const SizedBox(height: 10),

                       TextField(
                         controller: addressCtrl, 
                         decoration: const InputDecoration(
                           labelText: "Address", 
                           icon: Icon(Icons.location_on, size: 20),
                           isDense: true,
                           contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                         ),
                         minLines: 1, 
                         maxLines: 3, 
                         keyboardType: TextInputType.streetAddress,
                         style: const TextStyle(fontSize: 14),
                       ),
                       const SizedBox(height: 10),

                       TextField(
                         controller: contentCtrl, 
                         decoration: const InputDecoration(
                           labelText: "Help Content", 
                           icon: Icon(Icons.description, size: 20),
                           isDense: true,
                           contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                         ),
                         minLines: 1, 
                         maxLines: 5, 
                         keyboardType: TextInputType.multiline,
                         style: const TextStyle(fontSize: 14),
                       ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null), 
                  child: const Text("Cancel")
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text("SEND NOW"),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 5. MAIN UI BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Map
          const WebViewTab(),
          
          // Tab 1: SMS Inbox
          SmsTab(
            sosList: sosMessages, 
            otherList: otherMessages, 
            isLoading: isLoading, 
            onMove: _moveMessage, 
            onManualSend: _handleManualSend
          ),
          
          // Tab 2: Settings
          ConfigTab(onConfigSaved: _triggerPendingAnalysis),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.public), 
            label: "Rescue Map"
          ),
          NavigationDestination(
            icon: Icon(Icons.mark_chat_unread), 
            label: "Inbox"
          ),
          NavigationDestination(
            icon: Icon(Icons.settings), 
            label: "Config"
          ),
        ],
      ),
    );
  }
}