import 'package:flutter/material.dart';
import '../../data/local/prefs_helper.dart';

class ConfigTab extends StatefulWidget {
  const ConfigTab({super.key});
  @override
  State<ConfigTab> createState() => _ConfigTabState();
}

class _ConfigTabState extends State<ConfigTab> {
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
    
    if (mounted) setState(() {
      _autoSend = autoSend;
      _apiKeyController.text = apiKey;
      _refreshInterval = interval;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text("Automation", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          Card(
            child: SwitchListTile(
              title: const Text("Auto-Send SOS"),
              subtitle: const Text("Send requests to server after AI analysis."),
              value: _autoSend,
              activeColor: Colors.red,
              onChanged: (val) async {
                await PrefsHelper.setAutoSend(val);
                setState(() => _autoSend = val);
              },
            ),
          ),
          const SizedBox(height: 20),
          const Text("Display", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          Card(
            child: ListTile(
              title: const Text("WebView Auto-Refresh"),
              trailing: DropdownButton<int>(
                value: _refreshInterval,
                underline: Container(),
                items: const [
                  DropdownMenuItem(value: 10, child: Text("10 Seconds")),
                  DropdownMenuItem(value: 30, child: Text("30 Seconds")),
                  DropdownMenuItem(value: 60, child: Text("60 Seconds")),
                ],
                onChanged: (val) async {
                  if (val != null) {
                    await PrefsHelper.setRefreshInterval(val);
                    setState(() => _refreshInterval = val);
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text("AI Configuration", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _apiKeyController,
                decoration: const InputDecoration(labelText: "Gemini API Key", border: OutlineInputBorder()),
                obscureText: true,
                onChanged: (val) => PrefsHelper.setApiKey(val),
              ),
            ),
          ),
        ],
      ),
    );
  }
}