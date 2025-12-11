import 'package:shared_preferences/shared_preferences.dart';

class PrefsHelper {
  static const String _keyAutoSend = 'auto_send';
  static const String _keyApiKey = 'gemini_api_key';
  static const String _keyRefreshInterval = 'webview_refresh_interval';

  static Future<bool> getAutoSend() async => (await SharedPreferences.getInstance()).getBool(_keyAutoSend) ?? false;
  static Future<void> setAutoSend(bool value) async => (await SharedPreferences.getInstance()).setBool(_keyAutoSend, value);

  static Future<String> getApiKey() async => (await SharedPreferences.getInstance()).getString(_keyApiKey) ?? "";
  static Future<void> setApiKey(String value) async => (await SharedPreferences.getInstance()).setString(_keyApiKey, value);

  static Future<int> getRefreshInterval() async => (await SharedPreferences.getInstance()).getInt(_keyRefreshInterval) ?? 30;
  static Future<void> setRefreshInterval(int value) async => (await SharedPreferences.getInstance()).setInt(_keyRefreshInterval, value);
}