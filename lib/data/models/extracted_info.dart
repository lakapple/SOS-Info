import 'dart:convert';
import 'request_type.dart';

class ExtractedInfo {
  final List<String> phoneNumbers;
  final String content;
  final int peopleCount;
  final String address;
  // --- LOCATION FIELDS ---
  final double lat;
  final double lng;
  // -----------------------
  final RequestType requestType;
  final bool isAnalyzed;
  final bool needsRetry; // RESTORED THIS FIELD

  ExtractedInfo({
    this.phoneNumbers = const [],
    this.content = "",
    this.peopleCount = 0,
    this.address = "",
    this.lat = 0.0,
    this.lng = 0.0,
    this.requestType = RequestType.CUSTOM,
    this.isAnalyzed = false,
    this.needsRetry = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'phoneNumbers': jsonEncode(phoneNumbers),
      'content': content,
      'peopleCount': peopleCount,
      'address': address,
      'lat': lat,
      'lng': lng,
      'requestType': requestType.name,
      'isAnalyzed': isAnalyzed ? 1 : 0,
      // We don't necessarily need to save needsRetry to DB as it's transient
    };
  }

  factory ExtractedInfo.fromJson(Map<String, dynamic> map) {
    RequestType type = RequestType.CUSTOM;
    for (var val in RequestType.values) {
      if (val.name == map['requestType']) type = val;
    }

    return ExtractedInfo(
      phoneNumbers: List<String>.from(jsonDecode(map['phoneNumbers'])),
      content: map['content'] ?? "",
      peopleCount: map['peopleCount'] ?? 0,
      address: map['address'] ?? "",
      lat: map['lat'] ?? 0.0,
      lng: map['lng'] ?? 0.0,
      requestType: type,
      isAnalyzed: map['isAnalyzed'] == 1,
      needsRetry: false,
    );
  }
}