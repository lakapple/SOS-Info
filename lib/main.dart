import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ui/home_screen.dart';

void main() {
  runApp(const ProviderScope(child: MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'SOS Rescue',
    home: HomeScreen(),
  )));
}