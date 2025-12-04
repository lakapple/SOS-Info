import 'package:shared_preferences/shared_preferences.dart';

class PrefsHelper {
  static const String _keyAutoSend = 'auto_send';
  static const String _keyApiKey = 'gemini_api_key';

  // --- Auto Send ---
  static Future<bool> getAutoSend() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoSend) ?? false; // Default: False (Manual)
  }

  static Future<void> setAutoSend(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSend, value);
  }

  // --- API Key ---
  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiKey) ?? ""; // Default empty
  }

  static Future<void> setApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, value);
  }
}