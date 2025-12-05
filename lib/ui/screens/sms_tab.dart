import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/rescue_message.dart';
import '../../data/models/extracted_info.dart';
import '../../data/models/request_type.dart';
import '../../data/providers/rescue_provider.dart';
import '../widgets/sos_card.dart';

class SmsTab extends ConsumerWidget {
  const SmsTab({super.key});

  // --- MANUAL SEND HANDLER ---
  Future<void> _handleManualSend(BuildContext context, WidgetRef ref, RescueMessage msg) async {
    final notifier = ref.read(rescueProvider.notifier);
    
    // 1. Show Form
    ExtractedInfo? editedInfo = await _showEditDialog(context, msg);
    if (editedInfo == null) return; 

    // 2. Update via Provider
    notifier.updateMessageInfo(msg, editedInfo);
    
    // 3. Send
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sending...")));
    bool success = await notifier.performSend(msg);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Sent!")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Failed to send")));
    }
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
              contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(), 
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       const Text("Reference Message (Long press to copy):", style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                       const SizedBox(height: 4),
                       Container(
                         constraints: const BoxConstraints(maxHeight: 120),
                         padding: const EdgeInsets.all(8),
                         decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                         child: SingleChildScrollView(
                           child: SelectableText(msg.originalMessage.body ?? "", style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
                         ),
                       ),
                       const SizedBox(height: 15), const Divider(),
                       TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Phones", icon: Icon(Icons.phone), isDense: true)),
                       const SizedBox(height: 10),
                       DropdownButtonFormField<RequestType>(
                          value: selectedType,
                          decoration: const InputDecoration(labelText: "Type", icon: Icon(Icons.category), isDense: true),
                          isExpanded: true,
                          items: RequestType.values.map((type) => DropdownMenuItem(value: type, child: Text(type.vietnameseName, overflow: TextOverflow.ellipsis))).toList(),
                          onChanged: (val) { if(val != null) setDialogState(() => selectedType = val); },
                       ),
                       const SizedBox(height: 10),
                       TextField(controller: peopleCtrl, decoration: const InputDecoration(labelText: "People", icon: Icon(Icons.group), isDense: true), keyboardType: TextInputType.number),
                       const SizedBox(height: 10),
                       TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: "Address", icon: Icon(Icons.location_on), isDense: true), minLines: 1, maxLines: 3),
                       const SizedBox(height: 10),
                       TextField(controller: contentCtrl, decoration: const InputDecoration(labelText: "Content", icon: Icon(Icons.description), isDense: true), minLines: 1, maxLines: 5),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text("Cancel")),
                FilledButton.icon(
                  icon: const Icon(Icons.send, size: 16), label: const Text("SEND NOW"), style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch State
    final rescueState = ref.watch(rescueProvider);
    final notifier = ref.read(rescueProvider.notifier);

    if (rescueState.isLoading) return const Center(child: CircularProgressIndicator());
    
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
          _buildList(context, ref, rescueState.sosMessages, true),
          _buildList(context, ref, rescueState.otherMessages, false),
        ]),
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, List<RescueMessage> messages, bool isSosTab) {
    if (messages.isEmpty) return const Center(child: Text("No messages"));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final item = messages[index];
        final notifier = ref.read(rescueProvider.notifier);

        if (isSosTab) {
          return SosCard(
            message: item, 
            onManualSend: (m) => _handleManualSend(context, ref, m), 
            onMove: (m) => notifier.moveMessage(m, false)
          );
        } else {
          return Card(
            color: Colors.white,
            child: ExpansionTile(
              shape: const Border(),
              leading: const Icon(Icons.message, color: Colors.grey),
              title: Text(item.sender, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(item.originalMessage.body ?? "", maxLines: 1, overflow: TextOverflow.ellipsis),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16), 
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text("Full Message:", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(item.originalMessage.body ?? ""),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => notifier.moveMessage(item, true), 
                        child: const Text("Move to SOS")
                      )
                    )
                  ])
                )
              ],
            ),
          );
        }
      },
    );
  }
}