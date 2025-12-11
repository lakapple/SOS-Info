import 'package:flutter/material.dart';
import '../../data/models/rescue_message.dart';
import '../../data/models/request_type.dart';

class SosCard extends StatelessWidget {
  final RescueMessage message;
  final VoidCallback onSend;
  final VoidCallback onMove;

  const SosCard({super.key, required this.message, required this.onSend, required this.onMove});

  @override
  Widget build(BuildContext context) {
    final info = message.info;
    
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      color: Theme.of(context).colorScheme.errorContainer,
      child: ExpansionTile(
        shape: const Border(), collapsedShape: const Border(),
        leading: message.isAnalyzing 
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.priority_high, color: Colors.red),
        title: Text(info.phoneNumbers.isNotEmpty ? info.phoneNumbers.first : message.sender, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(message.originalMessage.body ?? "", maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.black.withOpacity(0.7))),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!info.isAnalyzed) ...[
                 const Center(child: LinearProgressIndicator()), 
                 const SizedBox(height: 10),
                 const Text("AI is analyzing...", style: TextStyle(color: Colors.grey)),
                 const SizedBox(height: 10),
              ] else ...[
                 _row(Icons.phone, "Phones", info.phoneNumbers.join(", "), Colors.blue), const Divider(),
                 _row(Icons.category, "Type", info.requestType.vietnameseName, Colors.purple), const Divider(),
                 _row(Icons.group, "People", "${info.peopleCount}", Colors.orange), const Divider(),
                 _row(Icons.location_on, "Address", info.address, Colors.red), const Divider(),
                 _row(Icons.description, "Content", info.content, Colors.black87), const SizedBox(height: 15),
              ],
              const Text("Full Message:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey)),
              Container(
                width: double.infinity, padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.black12)),
                child: SelectableText(message.originalMessage.body ?? "", style: const TextStyle(fontSize: 15)),
              ),
              const SizedBox(height: 15),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                FilledButton.icon(
                  onPressed: message.apiSent ? null : onSend,
                  icon: Icon(message.apiSent ? Icons.check : Icons.cloud_upload),
                  label: Text(message.apiSent ? "Sent" : "SEND ALERT"),
                  style: FilledButton.styleFrom(backgroundColor: message.apiSent ? Colors.green : Colors.red),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onMove, child: const Text("Not SOS"))
              ])
            ]),
          )
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String val, Color color) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 20, color: color), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(val.isEmpty ? "-" : val, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500))
      ]))
    ]);
  }
}