import 'package:flutter/material.dart';
import '../../data/models/rescue_message.dart';
import '../widgets/sos_card.dart';

class SmsTab extends StatelessWidget {
  final List<RescueMessage> sosList;
  final List<RescueMessage> otherList;
  final bool isLoading;
  final Function(RescueMessage, bool) onMove;
  final Function(RescueMessage) onManualSend;

  const SmsTab({
    super.key, required this.sosList, required this.otherList, required this.isLoading,
    required this.onMove, required this.onManualSend
  });

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
          _buildList(sosList, true),
          _buildList(otherList, false),
        ]),
      ),
    );
  }

  Widget _buildList(List<RescueMessage> messages, bool isSosTab) {
    if (messages.isEmpty) return const Center(child: Text("No messages"));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final item = messages[index];
        if (isSosTab) {
          return SosCard(message: item, onManualSend: onManualSend, onMove: (m) => onMove(m, false));
        } else {
          // Other Card (Expandable, Raw Text visible)
          return Card(
            color: Colors.white,
            child: ExpansionTile(
              shape: const Border(),
              leading: const Icon(Icons.message, color: Colors.grey),
              title: Text(item.originalMessage.address ?? "Unknown"),
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
                      child: TextButton(onPressed: () => onMove(item, true), child: const Text("Move to SOS"))
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