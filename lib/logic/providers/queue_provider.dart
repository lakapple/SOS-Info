import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../data/remote/gemini_service.dart';
import '../../data/remote/rescue_api_service.dart';
import '../../data/local/db_helper.dart';
import '../../data/models/rescue_message.dart';
import 'settings_provider.dart';
import 'sms_provider.dart';

class QueueNotifier extends StateNotifier<bool> {
  final Ref ref;
  final List<RescueMessage> _queue = [];
  bool _isRunning = false;

  QueueNotifier(this.ref) : super(false);

  void addToQueue(RescueMessage msg) {
    if (_queue.any((m) => m.originalMessage.date == msg.originalMessage.date)) return;
    _queue.add(msg);
    _process();
  }

  Future<void> _process() async {
    if (_isRunning) return;
    _isRunning = true;
    state = true; 

    while (_queue.isNotEmpty) {
      final msg = _queue.first;
      
      // Update status to Analyzing
      ref.read(smsProvider.notifier).updateLocalStatus(msg, isAnalyzing: true);

      // Check if user edited while queued
      final currentMsg = ref.read(smsProvider).sosList.firstWhere(
        (m) => m.originalMessage.date == msg.originalMessage.date, 
        orElse: () => msg
      );

      if (currentMsg.hasManualOverride) {
        _queue.removeAt(0);
        ref.read(smsProvider.notifier).updateLocalStatus(currentMsg, isAnalyzing: false);
        continue;
      }

      final settings = ref.read(settingsProvider);
      
      final result = await GeminiService().analyze(
        msg.originalMessage.body ?? "", 
        msg.sender, 
        settings.apiKey
      );

      if (result.needsRetry) {
        await Future.delayed(const Duration(seconds: 20));
        continue; 
      }

      if (result.isAnalyzed) {
        await DatabaseHelper.instance.saveState(
          msg.sender, msg.originalMessage.date ?? 0, result, msg.isSos
        );
      }

      // Update UI with Result
      ref.read(smsProvider.notifier).updateLocalInfo(msg, result);
      _queue.removeAt(0);

      // Auto Send
      if (settings.autoSend && result.isAnalyzed && !msg.apiSent) {
        await sendAlert(msg.copyWith(info: result));
      }

      await Future.delayed(const Duration(seconds: 5));
    }

    _isRunning = false;
    state = false;
  }

  Future<bool> sendAlert(RescueMessage msg) async {
    Position? pos;
    try { pos = await Geolocator.getCurrentPosition(); } catch (_) {}
    
    final success = await RescueApiService().sendRequest(msg.info, pos);
    if (success) {
      ref.read(smsProvider.notifier).updateLocalStatus(msg, apiSent: true);
    }
    return success;
  }
}

final queueProvider = StateNotifierProvider<QueueNotifier, bool>((ref) => QueueNotifier(ref));