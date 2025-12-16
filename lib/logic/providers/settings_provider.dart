import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/prefs_helper.dart';

class SettingsState {
  final bool autoSend;
  final String apiKey;
  final int refreshInterval;
  SettingsState({this.autoSend = false, this.apiKey = '', this.refreshInterval = 0});
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(SettingsState()) {
    _load();
  }

  Future<void> _load() async {
    state = SettingsState(
      autoSend: await PrefsHelper.getAutoSend(),
      apiKey: await PrefsHelper.getApiKey(),
      refreshInterval: await PrefsHelper.getRefreshInterval(),
    );
  }

  Future<void> saveAll(bool autoSend, String apiKey, int interval) async {
    await PrefsHelper.setAutoSend(autoSend);
    await PrefsHelper.setApiKey(apiKey);
    await PrefsHelper.setRefreshInterval(interval);
    await _load();
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) => SettingsNotifier());