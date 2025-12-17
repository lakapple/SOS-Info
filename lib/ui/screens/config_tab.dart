import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../logic/providers/settings_provider.dart';
import '../../logic/providers/sms_provider.dart';

class ConfigTab extends ConsumerStatefulWidget {
  const ConfigTab({super.key});

  @override
  ConsumerState<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<ConfigTab> {
  final _keyCtrl = TextEditingController();
  
  // Local state for UI changes before saving
  bool _autoSend = false;
  int _refresh = 30;

  @override
  void initState() {
    super.initState();
    // Load initial values from Provider
    final s = ref.read(settingsProvider);
    _keyCtrl.text = s.apiKey;
    _autoSend = s.autoSend;
    _refresh = s.refreshInterval;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Settings")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Automation Section
          Card(
            child: SwitchListTile(
              title: const Text("Auto-Send SOS"),
              subtitle: const Text("Send to server automatically after AI analysis"),
              value: _autoSend,
              activeColor: Colors.red,
              onChanged: (v) => setState(() => _autoSend = v),
            ),
          ),
          const SizedBox(height: 10),

          // Display Section
          Card(
            child: ListTile(
              title: const Text("Web Refresh Interval"),
              subtitle: const Text("Reload map periodically"),
              trailing: DropdownButton<int>(
                value: _refresh,
                underline: Container(),
                items: const [
                  DropdownMenuItem(value: 0, child: Text("Off")),
                  DropdownMenuItem(value: 10, child: Text("10s")),
                  DropdownMenuItem(value: 30, child: Text("30s")),
                  DropdownMenuItem(value: 60, child: Text("60s")),
                ],
                onChanged: (v) => setState(() => _refresh = v!),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // AI Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _keyCtrl,
                decoration: const InputDecoration(
                  labelText: "Gemini API Key",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.key),
                ),
                obscureText: true,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Save Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: () async {
                // 1. Save Settings
                await ref.read(settingsProvider.notifier).saveAll(
                  _autoSend, 
                  _keyCtrl.text.trim(), 
                  _refresh
                );
                
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("✅ Saved!"), backgroundColor: Colors.green)
                  );
                }

                // 2. Retry Failed Messages
                final c = ref.read(smsProvider.notifier).retryFailed();
                
                if (c > 0 && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Queueing $c messages for analysis..."))
                  );
                }
              },
              icon: const Icon(Icons.save),
              label: const Text("SAVE & APPLY"),
            ),
          )
        ],
      ),
    );
  }
}