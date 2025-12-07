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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    
    // 1. Initialize Controller
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() => _isLoading = true),
        onPageFinished: (_) => setState(() => _isLoading = false),
      ))
      ..loadRequest(Uri.parse(AppConstants.webViewUrl));

    // 2. Initialize Timer based on current setting (using read, not watch)
    final initialInterval = ref.read(settingsProvider).refreshInterval;
    _updateTimer(initialInterval);
  }

  // Logic to Start/Stop Timer
  void _updateTimer(int seconds) {
    _timer?.cancel(); // Always cancel old timer first

    if (seconds > 0) {
      debugPrint("🔄 WebView Timer started: Every $seconds seconds");
      _timer = Timer.periodic(Duration(seconds: seconds), (t) {
        debugPrint("🔄 Auto-refreshing WebView...");
        controller.reload();
      });
    } else {
      debugPrint("🛑 WebView Auto-refresh Disabled");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 3. LISTEN to Settings Changes
    // This is the correct way to react to provider changes for logic (not UI)
    ref.listen(settingsProvider.select((s) => s.refreshInterval), (previous, next) {
      if (previous != next) {
        _updateTimer(next);
      }
    });

    return Scaffold(
      // The WebView
      body: Stack(
        children: [
          SafeArea(child: WebViewWidget(controller: controller)),
          if (_isLoading)
            const LinearProgressIndicator(minHeight: 2, color: Colors.blue),
        ],
      ),
      
      // Manual Refresh Button
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: Colors.white.withOpacity(0.9),
        foregroundColor: Colors.blue,
        onPressed: () {
          controller.reload();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Refreshing Map..."), 
              duration: Duration(seconds: 1),
            )
          );
        },
        child: const Icon(Icons.refresh),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}