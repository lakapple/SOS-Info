import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/settings_provider.dart';
import '../../logic/sms_provider.dart';

class ConfigTab extends ConsumerStatefulWidget {
  const ConfigTab({super.key});
  @override
  ConsumerState<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<ConfigTab> {
  final _apiKeyCtrl = TextEditingController();
  bool _autoSend = false;
  int _refresh = 30;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _apiKeyCtrl.text = s.apiKey;
    _autoSend = s.autoSend;
    _refresh = s.refreshInterval;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SwitchListTile(title: const Text("Auto-Send SOS"), value: _autoSend, onChanged: (v) => setState(() => _autoSend = v)),
        ListTile(title: const Text("Web Refresh"), trailing: DropdownButton<int>(
          value: _refresh,
          items: const [
            DropdownMenuItem(value: 0, child: Text("Off")),
            DropdownMenuItem(value: 10, child: Text("10s")),
            DropdownMenuItem(value: 30, child: Text("30s")),
            DropdownMenuItem(value: 60, child: Text("60s")),
          ],
          onChanged: (v) => setState(() => _refresh = v!),
        )),
        TextField(controller: _apiKeyCtrl, decoration: const InputDecoration(labelText: "API Key", border: OutlineInputBorder()), obscureText: true),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 50, child: FilledButton.icon(
          onPressed: () async {
            await ref.read(settingsProvider.notifier).saveAll(_autoSend, _apiKeyCtrl.text.trim(), _refresh);
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Saved!"), backgroundColor: Colors.green));
            final c = ref.read(smsProvider.notifier).retryFailed();
            if (c > 0 && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Queueing $c messages...")));
          },
          icon: const Icon(Icons.save), label: const Text("SAVE & APPLY")
        ))
      ]),
    );
  }
}