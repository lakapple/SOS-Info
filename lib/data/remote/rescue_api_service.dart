import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../models/extracted_info.dart';
import '../models/request_type.dart';

class RescueApiService {
  Future<bool> sendRequest(ExtractedInfo info, Position? pos) async {
    try {
      final body = {
        "username": "Vô danh",
        "reporter": "App User",
        "type": info.requestType.vietnameseName,
        "phones": info.phoneNumbers.map((p) => AppUtils.formatPhoneNumber(p)).toList(),
        "content": info.content,
        "total_people": info.peopleCount,
        "address": info.address,
        "lat": pos?.latitude ?? 0.0,
        "lng": pos?.longitude ?? 0.0,
        "status": "Chưa duyệt",
        "timestamp": DateTime.now().toIso8601String(),
      };

      final res = await http.post(
        Uri.parse(AppConstants.rescueApiUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}