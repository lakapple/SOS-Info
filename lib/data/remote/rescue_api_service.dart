import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart'; // For DebugPrint
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../models/extracted_info.dart';
import '../models/request_type.dart';

class RescueApiService {
  static Future<bool> sendRequest(ExtractedInfo info, Position? pos) async {
    try {
      List<String> formattedPhones = info.phoneNumbers.map((p) => AppUtils.formatPhoneNumber(p)).toList();

      final bodyMap = {
        "username": "Vô danh",
        "reporter": "App User",
        "type": info.requestType.vietnameseName,
        "phones": formattedPhones,
        "content": info.content,
        "total_people": info.peopleCount,
        "address": info.address,
        "lat": pos?.latitude ?? 0.0,
        "lng": pos?.longitude ?? 0.0,
        "status": "Chưa duyệt",
        "timestamp": DateTime.now().toIso8601String(),
      };

      debugPrint("🚀 Sending API: ${jsonEncode(bodyMap)}");

      final response = await http.post(
        Uri.parse(AppConstants.rescueApiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(bodyMap),
      );

      debugPrint("Response: ${response.statusCode}");
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint("API Error: $e");
      return false;
    }
  }
}