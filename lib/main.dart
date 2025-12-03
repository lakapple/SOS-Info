import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:telephony/telephony.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

// Imports
import 'gemini_service.dart';
import 'db_helper.dart'; // Import Database Helper

// ---------------------------------------------------------
// MODEL CLASS
// ---------------------------------------------------------
class RescueMessage {
  final SmsMessage originalMessage;
  ExtractedInfo info; 
  bool isSos;
  bool apiSent;
  bool isAnalyzing; 

  RescueMessage({
    required this.originalMessage, 
    required this.info, 
    required this.isSos, 
    this.apiSent = false,
    this.isAnalyzing = false,
  });
}

// ---------------------------------------------------------
// MAIN ENTRY
// ---------------------------------------------------------
void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: AppRoot(),
  ));
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
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
    _initSmsListener();
  }

  String _formatPhoneNumber(String phone) {
    String p = phone.replaceAll(RegExp(r'\s+'), '').trim();
    if (p.startsWith("+84")) return "0${p.substring(3)}";
    return p;
  }

  // -------------------------------------------------------
  // QUEUE PROCESSOR (With DB Caching)
  // -------------------------------------------------------
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

      // 1. Call Gemini
      final result = await GeminiService.extractData(
        msg.originalMessage.body ?? "", 
        msg.originalMessage.address ?? "Unknown"
      );

      if (result.needsRetry) {
        debugPrint("⚠️ Rate Limit Hit! Waiting 20s...");
        await Future.delayed(const Duration(seconds: 20));
        continue;
      }

      // 2. Save to Database
      if (result.isAnalyzed) {
         await DatabaseHelper.instance.cacheAnalysis(
           msg.originalMessage.address ?? "Unknown", 
           msg.originalMessage.date ?? 0, 
           result
         );
      }

      _processingQueue.removeAt(0);
      if (mounted) {
        setState(() {
          msg.info = result;
          msg.isAnalyzing = false;
        });
      }

      await Future.delayed(const Duration(seconds: 5));
    }
    _isProcessorRunning = false;
  }

  // -------------------------------------------------------
  // LOAD MESSAGES (Check DB First)
  // -------------------------------------------------------
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
      
      // 1. Check Database Cache
      ExtractedInfo cachedInfo = ExtractedInfo();
      if (isSos) {
        final dbResult = await DatabaseHelper.instance.getCachedAnalysis(
          sms.address ?? "Unknown", 
          sms.date ?? 0
        );
        if (dbResult != null) {
          cachedInfo = dbResult; // Use cached result
        }
      }

      var msgObj = RescueMessage(
        originalMessage: sms, 
        info: cachedInfo, // Pass extracted info (empty or cached)
        isSos: isSos,
      );

      if (isSos) {
        tempSos.add(msgObj);
      } else {
        if (otherCount < 50) { 
          tempOther.add(msgObj);
          otherCount++;
        }
      }
    }

    if (mounted) {
      setState(() {
        sosMessages = tempSos;
        otherMessages = tempOther;
        isLoading = false;
      });

      // Only add to queue if NOT already analyzed
      for (var msg in sosMessages) {
        if (!msg.info.isAnalyzed) {
          _addToAnalysisQueue(msg);
        }
      }
    }
  }

  Future<void> _initSmsListener() async {
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) { _loadMessages(); },
      onBackgroundMessage: backgroundMessageHandler,
    );
  }
  
  static void backgroundMessageHandler(SmsMessage message) {}

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

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sending...")));

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      debugPrint("Location Error: $e");
    }

    await _sendToRescueServer(msg.info, pos);
    setState(() => msg.apiSent = true);
  }

  Future<void> _sendToRescueServer(ExtractedInfo info, Position? pos) async {
    try {
      List<String> formattedPhones = info.phoneNumbers.map((p) => _formatPhoneNumber(p)).toList();
      String requestTypeString;
      switch (info.requestType) {
        case RequestType.URGENT_HOSPITAL: requestTypeString = "Đi viện gấp"; break;
        case RequestType.SAFE_PLACE: requestTypeString = "Đến nơi an toàn"; break;
        case RequestType.SUPPLIES: requestTypeString = "Nhu yếu phẩm"; break;
        case RequestType.MEDICAL: requestTypeString = "Thiết bị y tế"; break;
        case RequestType.CLOTHES: requestTypeString = "Quần áo"; break;
        case RequestType.CUSTOM: requestTypeString = "Tự viết yêu cầu riêng"; break;
      }

      final bodyMap = {
        "username": "Vô danh",
        "reporter": "App User",
        "type": requestTypeString,
        "phones": formattedPhones,
        "content": info.content,
        "total_people": info.peopleCount,
        "address": info.address,
        "lat": pos?.latitude ?? 0.0,
        "lng": pos?.longitude ?? 0.0,
        "status": "Chưa duyệt",
        "timestamp": DateTime.now().toIso8601String(),
      };

      final response = await http.post(
        Uri.parse('https://sg1.sos.info.vn/api/requests'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(bodyMap),
      );

      if (mounted) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Sent Successfully!")));
        } else {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("⚠️ Server Error: ${response.statusCode}")));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const WebViewTab(),
          SmsManagerTab(
            sosList: sosMessages,
            otherList: otherMessages,
            isLoading: isLoading,
            onMove: _moveMessage,
            onManualSend: _handleManualSend,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: "Map"),
          NavigationDestination(icon: Icon(Icons.mark_chat_unread), label: "Inbox"),
        ],
      ),
    );
  }
}

class WebViewTab extends StatefulWidget {
  const WebViewTab({super.key});
  @override
  State<WebViewTab> createState() => _WebViewTabState();
}
class _WebViewTabState extends State<WebViewTab> {
  late final WebViewController controller;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted)..loadRequest(Uri.parse('https://demo.sos.info.vn'));
    _timer = Timer.periodic(const Duration(seconds: 30), (t) => controller.reload());
  }
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => SafeArea(child: WebViewWidget(controller: controller));
}

class SmsManagerTab extends StatelessWidget {
  final List<RescueMessage> sosList;
  final List<RescueMessage> otherList;
  final bool isLoading;
  final Function(RescueMessage, bool) onMove;
  final Function(RescueMessage) onManualSend;

  const SmsManagerTab({super.key, required this.sosList, required this.otherList, required this.isLoading, required this.onMove, required this.onManualSend});

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("Message Center"),
          bottom: const TabBar(tabs: [
            Tab(text: "SOS / HELP", icon: Icon(Icons.warning_amber_rounded)),
            Tab(text: "OTHER SMS", icon: Icon(Icons.message_outlined)),
          ]),
        ),
        body: TabBarView(children: [
          _buildList(context, sosList, true),
          _buildList(context, otherList, false),
        ]),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<RescueMessage> messages, bool isSosTab) {
    if (messages.isEmpty) return const Center(child: Text("No messages"));
    
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final item = messages[index];
        final info = item.info;
        final colorScheme = Theme.of(context).colorScheme;

        // ---------------------------------------------------------
        // UI FOR "OTHER SMS" (NOW CLICKABLE/EXPANDABLE)
        // ---------------------------------------------------------
        if (!isSosTab) {
          return Card(
            color: Colors.white,
            child: ExpansionTile(
              leading: const Icon(Icons.message, color: Colors.grey),
              title: Text(item.originalMessage.address ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                item.originalMessage.body ?? "",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Raw Content:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                      const SizedBox(height: 5),
                      Text(item.originalMessage.body ?? "", style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 15),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: () => onMove(item, true),
                          icon: const Icon(Icons.arrow_upward),
                          label: const Text("Move to SOS"),
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
          );
        }

        // ---------------------------------------------------------
        // UI FOR "SOS" (EXISTING)
        // ---------------------------------------------------------
        return Card(
          color: colorScheme.errorContainer,
          child: ExpansionTile(
            leading: item.isAnalyzing 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.priority_high, color: Colors.red),
            title: Text(
              info.phoneNumbers.isNotEmpty ? info.phoneNumbers.first : (item.originalMessage.address ?? "Unknown"), 
              style: const TextStyle(fontWeight: FontWeight.bold)
            ),
            subtitle: Text(
              !info.isAnalyzed ? "Analyzing..." : info.content, 
              maxLines: 1, overflow: TextOverflow.ellipsis
            ),
            children: [
              if (!info.isAnalyzed)
                const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
              else
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      _buildInfoRow(Icons.phone, "Phones", info.phoneNumbers.join(", "), Colors.blue),
                      const Divider(),
                      _buildInfoRow(Icons.category, "Type", _getRequestTypeName(info.requestType), Colors.purple),
                      const Divider(),
                      _buildInfoRow(Icons.group, "People", "${info.peopleCount}", Colors.orange),
                      const Divider(),
                      _buildInfoRow(Icons.location_on, "Address", info.address, Colors.red),
                      const Divider(),
                      _buildInfoRow(Icons.summarize, "Summary", info.content, Colors.black87),
                      const Divider(thickness: 2),
                      const Align(alignment: Alignment.centerLeft, child: Text("Original Message:", style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold))),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        color: Colors.white.withOpacity(0.5),
                        child: Text(item.originalMessage.body ?? "", style: const TextStyle(fontStyle: FontStyle.italic)),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          FilledButton.icon(
                            onPressed: item.apiSent ? null : () => onManualSend(item),
                            icon: Icon(item.apiSent ? Icons.check : Icons.cloud_upload),
                            label: Text(item.apiSent ? "Sent" : "SEND ALERT"),
                            style: FilledButton.styleFrom(backgroundColor: item.apiSent ? Colors.green : Colors.red),
                          ),
                          const SizedBox(width: 8),
                          TextButton(onPressed: () => onMove(item, false), child: const Text("Not SOS")),
                        ],
                      )
                    ],
                  ),
                )
            ],
          ),
        );
      },
    );
  }

  String _getRequestTypeName(RequestType type) {
    switch (type) {
      case RequestType.URGENT_HOSPITAL: return "Đi viện gấp";
      case RequestType.SAFE_PLACE: return "Đến nơi an toàn";
      case RequestType.SUPPLIES: return "Nhu yếu phẩm";
      case RequestType.MEDICAL: return "Thiết bị y tế";
      case RequestType.CLOTHES: return "Quần áo";
      case RequestType.CUSTOM: return "Tự viết yêu cầu riêng";
    }
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color iconColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }
}