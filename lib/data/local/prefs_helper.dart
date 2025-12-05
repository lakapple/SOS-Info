import 'package:shared_preferences/shared_preferences.dart';

class PrefsHelper {
  static const String _keyAutoSend = 'auto_send';
  static const String _keyApiKey = 'gemini_api_key';
  static const String _keyRefreshInterval = 'webview_refresh_interval';

  static Future<bool> getAutoSend() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAutoSend) ?? false;
  }
  static Future<void> setAutoSend(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoSend, value);
  }

  static Future<String> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiKey) ?? "";
  }
  static Future<void> setApiKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiKey, value);
  }

  static Future<int> getRefreshInterval() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyRefreshInterval) ?? 30; // Default 30s
  }
  static Future<void> setRefreshInterval(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyRefreshInterval, value);
  }
}