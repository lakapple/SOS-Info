import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/constants.dart';

class WebViewTab extends StatefulWidget {
  const WebViewTab({super.key});
  @override
  State<WebViewTab> createState() => _WebViewTabState();
}

class _WebViewTabState extends State<WebViewTab> {
  late final WebViewController controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(AppConstants.webViewUrl));
    _timer = Timer.periodic(const Duration(seconds: 30), (t) => controller.reload());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(child: WebViewWidget(controller: controller));
}