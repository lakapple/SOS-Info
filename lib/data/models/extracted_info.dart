import 'dart:convert';
import 'request_type.dart';

class ExtractedInfo {
  final List<String> phoneNumbers;
  final String content;
  final int peopleCount;
  final String address;
  final RequestType requestType;
  final bool isAnalyzed;
  final bool needsRetry;

  ExtractedInfo({
    this.phoneNumbers = const [],
    this.content = "",
    this.peopleCount = 0,
    this.address = "",
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
      'requestType': requestType.name,
      'isAnalyzed': isAnalyzed ? 1 : 0,
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
      requestType: type,
      isAnalyzed: map['isAnalyzed'] == 1,
      needsRetry: false,
    );
  }
}