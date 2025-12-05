import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/rescue_provider.dart';
import 'webview_tab.dart';
import 'sms_tab.dart';
import 'config_tab.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Init Logic moved to Provider
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(rescueProvider.notifier).initPermissionsAndListeners();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          WebViewTab(),
          SmsTab(),
          ConfigTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.public), label: "Map"),
          NavigationDestination(icon: Icon(Icons.mark_chat_unread), label: "Inbox"),
          NavigationDestination(icon: Icon(Icons.settings), label: "Config"),
        ],
      ),
    );
  }
}