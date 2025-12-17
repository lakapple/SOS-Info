import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  static const _keyAutoSend = 'auto_send';
  static const _keyApiKey = 'gemini_api_key';
  static const _keyRefresh = 'webview_refresh';

  Future<bool> getAutoSend() async => (await SharedPreferences.getInstance()).getBool(_keyAutoSend) ?? false;
  Future<void> setAutoSend(bool val) async => (await SharedPreferences.getInstance()).setBool(_keyAutoSend, val);

  Future<String> getApiKey() async => (await SharedPreferences.getInstance()).getString(_keyApiKey) ?? "";
  Future<void> setApiKey(String val) async => (await SharedPreferences.getInstance()).setString(_keyApiKey, val);

  Future<int> getRefreshInterval() async => (await SharedPreferences.getInstance()).getInt(_keyRefresh) ?? 30;
  Future<void> setRefreshInterval(int val) async => (await SharedPreferences.getInstance()).setInt(_keyRefresh, val);
}