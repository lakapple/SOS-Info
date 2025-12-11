import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/sms_provider.dart';
import '../../data/models/extracted_info.dart';
import '../../data/models/request_type.dart';
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
          _buildList(context, ref, state.sosList, true),
          _buildList(context, ref, state.otherList, false),
        ]),
      ),
    );
  }

  Widget _buildList(BuildContext ctx, WidgetRef ref, List<RescueMessage> msgs, bool isSos) {
    if (msgs.isEmpty) return const Center(child: Text("No messages"));
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: msgs.length,
      itemBuilder: (_, i) {
        final msg = msgs[i];
        if (isSos) {
          return SosCard(
            message: msg,
            onMove: () => ref.read(smsProvider.notifier).moveMessage(msg, false),
            onSend: () => _manualSend(ctx, ref, msg),
          );
        } else {
          return Card(
            color: Colors.white,
            child: ExpansionTile(
              shape: const Border(),
              leading: const Icon(Icons.message, color: Colors.grey),
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

  Future<void> _manualSend(BuildContext context, WidgetRef ref, RescueMessage msg) async {
    final info = msg.info;
    final phoneCtrl = TextEditingController(text: info.phoneNumbers.join(", "));
    final peopleCtrl = TextEditingController(text: info.peopleCount.toString());
    final addrCtrl = TextEditingController(text: info.address);
    final contentCtrl = TextEditingController(text: info.content);
    RequestType type = info.requestType;

    final result = await showDialog<ExtractedInfo>(
      context: context, barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) => AlertDialog(
        title: const Text("Confirm & Edit"),
        contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
        content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 100),
              padding: const EdgeInsets.all(8), color: Colors.grey.shade100,
              child: SingleChildScrollView(child: SelectableText(msg.originalMessage.body ?? "", style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12))),
            ),
            const Divider(),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: "Phones", icon: Icon(Icons.phone), isDense: true)),
            const SizedBox(height: 10),
            DropdownButtonFormField<RequestType>(
              value: type, isExpanded: true,
              decoration: const InputDecoration(labelText: "Type", icon: Icon(Icons.category), isDense: true),
              items: RequestType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.vietnameseName, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => type = v!),
            ),
            const SizedBox(height: 10),
            TextField(controller: peopleCtrl, decoration: const InputDecoration(labelText: "People", icon: Icon(Icons.group), isDense: true), keyboardType: TextInputType.number),
            const SizedBox(height: 10),
            TextField(controller: addrCtrl, decoration: const InputDecoration(labelText: "Address", icon: Icon(Icons.location_on), isDense: true), minLines: 1, maxLines: 3),
            const SizedBox(height: 10),
            TextField(controller: contentCtrl, decoration: const InputDecoration(labelText: "Content", icon: Icon(Icons.description), isDense: true), minLines: 1, maxLines: 5),
          ]),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(onPressed: () {
            Navigator.pop(ctx, ExtractedInfo(
              phoneNumbers: phoneCtrl.text.split(',').map((e)=>e.trim()).toList(),
              content: contentCtrl.text,
              peopleCount: int.tryParse(peopleCtrl.text) ?? 1,
              address: addrCtrl.text,
              requestType: type,
              isAnalyzed: true
            ));
          }, child: const Text("SEND"))
        ],
      ))
    );

    if (result != null) {
      await ref.read(smsProvider.notifier).updateAndSave(msg, result);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sending...")));
      final success = await ref.read(smsProvider.notifier).sendAlert(msg);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? "✅ Sent!" : "⚠️ Failed")));
    }
  }
}