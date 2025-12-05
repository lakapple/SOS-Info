import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../local/prefs_helper.dart';

// State Class
class AppSettingsState {
  final bool autoSend;
  final String apiKey;
  final int refreshInterval;
  final bool isLoading;

  AppSettingsState({
    this.autoSend = false,
    this.apiKey = '',
    this.refreshInterval = 30,
    this.isLoading = true,
  });

  AppSettingsState copyWith({
    bool? autoSend,
    String? apiKey,
    int? refreshInterval,
    bool? isLoading,
  }) {
    return AppSettingsState(
      autoSend: autoSend ?? this.autoSend,
      apiKey: apiKey ?? this.apiKey,
      refreshInterval: refreshInterval ?? this.refreshInterval,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// Notifier
class SettingsNotifier extends StateNotifier<AppSettingsState> {
  SettingsNotifier() : super(AppSettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final autoSend = await PrefsHelper.getAutoSend();
    final apiKey = await PrefsHelper.getApiKey();
    final interval = await PrefsHelper.getRefreshInterval();
    
    state = state.copyWith(
      autoSend: autoSend,
      apiKey: apiKey,
      refreshInterval: interval,
      isLoading: false,
    );
  }

  Future<void> updateAutoSend(bool value) async {
    await PrefsHelper.setAutoSend(value);
    state = state.copyWith(autoSend: value);
  }

  Future<void> updateApiKey(String value) async {
    await PrefsHelper.setApiKey(value);
    state = state.copyWith(apiKey: value);
  }

  Future<void> updateRefreshInterval(int value) async {
    await PrefsHelper.setRefreshInterval(value);
    state = state.copyWith(refreshInterval: value);
  }
}

// Provider Definition
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettingsState>((ref) {
  return SettingsNotifier();
});