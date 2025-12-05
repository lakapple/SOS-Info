import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/constants.dart';
import '../../data/providers/settings_provider.dart';

class WebViewTab extends ConsumerStatefulWidget {
  const WebViewTab({super.key});
  @override
  ConsumerState<WebViewTab> createState() => _WebViewTabState();
}

class _WebViewTabState extends ConsumerState<WebViewTab> {
  late final WebViewController controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(AppConstants.webViewUrl));
  }

  void _setupTimer(int interval) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: interval), (t) => controller.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch settings to auto-update timer if interval changes
    final interval = ref.watch(settingsProvider.select((s) => s.refreshInterval));
    
    // We start/restart timer inside build side-effect or listener, 
    // but doing it here is a simple way to react to state changes.
    // Ideally use ref.listen, but simple check works for this scale.
    if (_timer == null || _timer!.tick > 0) { // lazy check
        _setupTimer(interval); 
    }

    return SafeArea(child: WebViewWidget(controller: controller));
  }
}