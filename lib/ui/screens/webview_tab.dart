import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/constants.dart';
import '../../logic/providers/settings_provider.dart';

class WebViewTab extends ConsumerStatefulWidget {
  final bool isVisible;
  const WebViewTab({super.key, required this.isVisible});
  @override
  ConsumerState<WebViewTab> createState() => _WebViewTabState();
}

class _WebViewTabState extends ConsumerState<WebViewTab> {
  late final WebViewController _ctrl;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _loading = true),
        onPageFinished: (_) => setState(() => _loading = false),
      ))
      ..loadRequest(Uri.parse(AppConstants.webViewUrl));
    _checkTimer();
  }

  void _checkTimer() {
    final sec = ref.read(settingsProvider).refreshInterval;
    _timer?.cancel();
    if (widget.isVisible && sec > 0) {
      _timer = Timer.periodic(Duration(seconds: sec), (_) => _ctrl.reload());
    }
  }

  @override
  void didUpdateWidget(WebViewTab old) {
    super.didUpdateWidget(old);
    if (widget.isVisible != old.isVisible) _checkTimer();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (_, __) => _checkTimer());
    return Scaffold(
      body: Stack(children: [
        SafeArea(child: WebViewWidget(controller: _ctrl)),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
      ]),
      floatingActionButton: FloatingActionButton(
        mini: true, onPressed: () => _ctrl.reload(), child: const Icon(Icons.refresh)
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}