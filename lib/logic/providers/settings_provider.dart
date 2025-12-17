import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/prefs_helper.dart';

class SettingsState {
  final bool autoSend;
  final String apiKey;
  final int refreshInterval;

  SettingsState({
    this.autoSend = false,
    this.apiKey = '',
    this.refreshInterval = 30,
  });
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final _repo = SettingsRepository();
  
  SettingsNotifier() : super(SettingsState()) {
    _load();
  }

  Future<void> _load() async {
    state = SettingsState(
      autoSend: await _repo.getAutoSend(),
      apiKey: await _repo.getApiKey(),
      refreshInterval: await _repo.getRefreshInterval(),
    );
  }

  Future<void> setApiKey(String key) async {
    await _repo.setApiKey(key);
    await _load();
  }

  Future<void> setAutoSend(bool val) async {
    await _repo.setAutoSend(val);
    await _load();
  }

  Future<void> setRefresh(int val) async {
    await _repo.setRefreshInterval(val);
    await _load();
  }

  // --- ADDED THIS MISSING METHOD ---
  Future<void> saveAll(bool autoSend, String apiKey, int interval) async {
    await _repo.setAutoSend(autoSend);
    await _repo.setApiKey(apiKey);
    await _repo.setRefreshInterval(interval);
    await _load(); // Refresh state
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});