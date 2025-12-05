import 'package:flutter/material.dart';
import '../../data/local/prefs_helper.dart';

class ConfigTab extends StatefulWidget {
  // Callback to trigger Main Screen logic (AI Analysis)
  final VoidCallback onConfigSaved; 

  const ConfigTab({super.key, required this.onConfigSaved});

  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
  // Local state for UI
  bool _autoSend = false;
  final TextEditingController _apiKeyController = TextEditingController();
  int _refreshInterval = 30;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final autoSend = await PrefsHelper.getAutoSend();
    final apiKey = await PrefsHelper.getApiKey();
    final interval = await PrefsHelper.getRefreshInterval();
    
    if (mounted) {
      setState(() {
        _autoSend = autoSend;
        _apiKeyController.text = apiKey;
        _refreshInterval = interval;
        _isLoading = false;
      });
    }
  }

  // --- SAVE ACTION ---
  Future<void> _handleSave() async {
    // 1. Save all settings to Preferences
    await PrefsHelper.setAutoSend(_autoSend);
    await PrefsHelper.setApiKey(_apiKeyController.text.trim());
    await PrefsHelper.setRefreshInterval(_refreshInterval);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ Configuration Saved & Applied!"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }

    // 2. Trigger the callback to Main Screen (Start AI)
    widget.onConfigSaved();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionHeader("Automation"),
          Card(
            // Fix: Use ListTile + trailing Switch so only the switch is clickable
            child: ListTile(
              title: const Text("Auto-Send SOS"),
              subtitle: const Text("Automatically send requests after AI analysis."),
              trailing: Switch(
                value: _autoSend,
                activeColor: Colors.red,
                onChanged: (val) {
                  setState(() => _autoSend = val);
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
                value: _refreshInterval,
                underline: Container(),
                items: const [
                  DropdownMenuItem(value: 10, child: Text("10s")),
                  DropdownMenuItem(value: 30, child: Text("30s")),
                  DropdownMenuItem(value: 60, child: Text("60s")),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _refreshInterval = val);
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
                    // ALWAYS ENABLED NOW
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
          
          // --- GLOBAL SAVE BUTTON ---
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _handleSave,
              icon: const Icon(Icons.save),
              label: const Text("SAVE & APPLY CONFIGURATION", style: TextStyle(fontWeight: FontWeight.bold)),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
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