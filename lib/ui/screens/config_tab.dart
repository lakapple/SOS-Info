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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final autoSend = await PrefsHelper.getAutoSend();
    final apiKey = await PrefsHelper.getApiKey();
    
    if (mounted) {
      setState(() {
        _autoSend = autoSend;
        _apiKeyController.text = apiKey;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveAutoSend(bool value) async {
    await PrefsHelper.setAutoSend(value);
    setState(() => _autoSend = value);
  }

  Future<void> _saveApiKey(String value) async {
    await PrefsHelper.setApiKey(value);
    // Note: No setState needed for text field as controller handles it
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildSectionHeader("Automation"),
          Card(
            child: SwitchListTile(
              title: const Text("Auto-Send SOS"),
              subtitle: const Text("Automatically send SOS requests to the server after AI analysis."),
              value: _autoSend,
              activeColor: Colors.red,
              onChanged: _saveAutoSend,
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
                      hintText: "Paste your Google Gemini API Key here",
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.key),
                      helperText: "Required for AI analysis",
                    ),
                    obscureText: true, // Hide key for security
                    onChanged: _saveApiKey,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          const Center(
            child: Text(
              "Version 1.0.0",
              style: TextStyle(color: Colors.grey),
            ),
          )
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