import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/settings_provider.dart';
import '../../data/providers/rescue_provider.dart';

class ConfigTab extends ConsumerStatefulWidget {
  const ConfigTab({super.key});

  @override
  ConsumerState<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends ConsumerState<ConfigTab> {
  final TextEditingController _apiKeyController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    // Pre-fill controller with current state
    final settings = ref.read(settingsProvider);
    _apiKeyController.text = settings.apiKey;
  }

  Future<void> _handleSave() async {
    // Save all via Provider
    final notifier = ref.read(settingsProvider.notifier);
    await notifier.updateApiKey(_apiKeyController.text.trim());
    // Auto-send and interval are already updated via their specific widgets below (onChanged)
    // But for API key in text field, we explicitly save here.

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Configuration Saved!"), backgroundColor: Colors.green),
      );
    }

    // Trigger AI Logic in Rescue Provider
    final count = ref.read(rescueProvider.notifier).triggerPendingAnalysis();
    if (count > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Queueing $count messages...")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch settings state
    final settings = ref.watch(settingsProvider);

    if (settings.isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionHeader("Automation"),
          Card(
            child: ListTile(
              title: const Text("Auto-Send SOS"),
              subtitle: const Text("Automatically send requests after AI analysis."),
              trailing: Switch(
                value: settings.autoSend,
                activeColor: Colors.red,
                onChanged: (val) {
                  ref.read(settingsProvider.notifier).updateAutoSend(val);
                },
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          _buildSectionHeader("Display Settings"),
          Card(
            child: ListTile(
              title: const Text("WebView Auto-Refresh"),
              subtitle: const Text("Interval for reloading the rescue map."),
              leading: const Icon(Icons.timer),
              trailing: DropdownButton<int>(
                value: settings.refreshInterval,
                underline: Container(),
                items: const [
                  DropdownMenuItem(value: 10, child: Text("10s")),
                  DropdownMenuItem(value: 30, child: Text("30s")),
                  DropdownMenuItem(value: 60, child: Text("60s")),
                ],
                onChanged: (val) {
                  if (val != null) {
                    ref.read(settingsProvider.notifier).updateRefreshInterval(val);
                  }
                },
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          _buildSectionHeader("AI Configuration"),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Gemini API Key", style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _apiKeyController,
                    decoration: const InputDecoration(
                      hintText: "Paste API Key here",
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.key),
                    ),
                    obscureText: true, 
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _handleSave,
              icon: const Icon(Icons.save),
              label: const Text("SAVE & APPLY", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14, 
          fontWeight: FontWeight.bold, 
          color: Theme.of(context).colorScheme.primary
        ),
      ),
    );
  }
}