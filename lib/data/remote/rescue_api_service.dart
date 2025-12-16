import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../models/extracted_info.dart';
import '../models/request_type.dart';

class RescueApiService {
  Future<bool> sendRequest(ExtractedInfo info, Position? currentPos) async {
    try {
      // Logic: Use the map-picked location (info.lat) if available.
      // If 0.0, fallback to current GPS (currentPos).
      double finalLat = (info.lat != 0.0) ? info.lat : (currentPos?.latitude ?? 0.0);
      double finalLng = (info.lng != 0.0) ? info.lng : (currentPos?.longitude ?? 0.0);

      final body = {
        "username": "Vô danh",
        "reporter": "App User",
        "type": info.requestType.vietnameseName,
        "phones": info.phoneNumbers.map((p) => AppUtils.formatPhoneNumber(p)).toList(),
        "content": info.content,
        "total_people": info.peopleCount,
        "address": info.address,
        "lat": finalLat,
        "lng": finalLng,
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