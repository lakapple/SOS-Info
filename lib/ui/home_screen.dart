import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../logic/providers/sms_provider.dart';
import 'screens/webview_tab.dart';
import 'screens/sms_tab.dart';
import 'screens/config_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(smsProvider.notifier).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _idx, children: [
        WebViewTab(isVisible: _idx == 0),
        const SmsTab(),
        const ConfigTab(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _idx,
        onDestinationSelected: (i) => setState(() => _idx = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: "Map"),
          NavigationDestination(icon: Icon(Icons.sms), label: "Inbox"),
          NavigationDestination(icon: Icon(Icons.settings), label: "Config"),
        ],
      ),
    );
  }
}