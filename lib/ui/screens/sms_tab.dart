import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers/sms_provider.dart';
import '../../data/models/rescue_message.dart';
import '../widgets/sos_card.dart';

class SmsTab extends ConsumerWidget {
  const SmsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(smsProvider);
    if (state.isLoading) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text("Inbox"), bottom: const TabBar(tabs: [
          Tab(text: "SOS / HELP", icon: Icon(Icons.warning)),
          Tab(text: "OTHER SMS", icon: Icon(Icons.message)),
        ])),
        body: TabBarView(children: [
          _buildList(ref, state.sosList, true),
          _buildList(ref, state.otherList, false),
        ]),
      ),
    );
  }

  Widget _buildList(WidgetRef ref, List<RescueMessage> msgs, bool isSos) {
    if (msgs.isEmpty) return const Center(child: Text("No messages"));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: msgs.length,
      itemBuilder: (_, i) {
        final msg = msgs[i];
        if (isSos) {
          return SosCard(message: msg, onMove: () => ref.read(smsProvider.notifier).moveMessage(msg, false));
        } else {
          return Card(
            color: Colors.white,
            child: ExpansionTile(
              shape: const Border(), leading: const Icon(Icons.message, color: Colors.grey),
              title: Text(msg.sender, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(msg.originalMessage.body ?? "", maxLines: 1, overflow: TextOverflow.ellipsis),
              children: [
                Padding(padding: const EdgeInsets.all(16), child: Column(children: [
                  const Align(alignment: Alignment.centerLeft, child: Text("Full Message:", style: TextStyle(fontWeight: FontWeight.bold))),
                  SelectableText(msg.originalMessage.body ?? ""),
                  Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => ref.read(smsProvider.notifier).moveMessage(msg, true), child: const Text("Move to SOS")))
                ]))
              ],
            ),
          );
        }
      },
    );
  }
}