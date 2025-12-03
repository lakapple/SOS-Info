import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------
// DATA MODEL
// ---------------------------------------------------------
enum RequestType {
  URGENT_HOSPITAL, SAFE_PLACE, SUPPLIES, MEDICAL, CLOTHES, CUSTOM
}

class ExtractedInfo {
  List<String> phoneNumbers;
  String content;
  int peopleCount;
  String address;
  RequestType requestType;
  bool isAnalyzed;
  bool needsRetry;

  ExtractedInfo({
    this.phoneNumbers = const [],
    this.content = "...",
    this.peopleCount = 0,
    this.address = "Analyzing...",
    this.requestType = RequestType.CUSTOM,
    this.isAnalyzed = false,
    this.needsRetry = false,
  });

  // --- NEW: Convert to Map for Database ---
  Map<String, dynamic> toJson() {
    return {
      'phoneNumbers': jsonEncode(phoneNumbers),
      'content': content,
      'peopleCount': peopleCount,
      'address': address,
      'requestType': requestType.name, // Save Enum as String
      'isAnalyzed': isAnalyzed ? 1 : 0, // SQLite uses 1/0 for bool
    };
  }

  // --- NEW: Create from Map (Database) ---
  factory ExtractedInfo.fromJson(Map<String, dynamic> map) {
    // Convert String back to Enum
    RequestType type = RequestType.CUSTOM;
    for (var val in RequestType.values) {
      if (val.name == map['requestType']) type = val;
    }

    return ExtractedInfo(
      phoneNumbers: List<String>.from(jsonDecode(map['phoneNumbers'])),
      content: map['content'],
      peopleCount: map['peopleCount'],
      address: map['address'],
      requestType: type,
      isAnalyzed: map['isAnalyzed'] == 1,
      needsRetry: false,
    );
  }
}

// ---------------------------------------------------------
// GEMINI SERVICE
// ---------------------------------------------------------
class GeminiService {
  static const String _apiKey = "AIzaSyDPFZI5rG-c8VURepHC2pbMqG0KMCrYay8"; // REPLACE THIS
  static const String _modelName = "gemini-2.5-flash-lite"; 

  static Future<ExtractedInfo> extractData(String smsBody, String senderPhone) async {
    try {
      final model = GenerativeModel(
        model: _modelName,
        apiKey: _apiKey,
        generationConfig: GenerationConfig(responseMimeType: "application/json", temperature: 0.1),
      );

      final prompt = Content.text('''
        Bạn là hệ thống AI cứu hộ khẩn cấp.
        Input:
        - Sender: $senderPhone
        - Message: "$smsBody"

        Trả về JSON duy nhất:
        {
          "phone_numbers": ["sdt1"],
          "content": "tóm tắt",
          "people_count": 1,
          "address": "địa chỉ",
          "request_type": "CUSTOM"
        }
        Valid types: URGENT_HOSPITAL, SAFE_PLACE, SUPPLIES, MEDICAL, CLOTHES, CUSTOM.
      ''');

      final response = await model.generateContent([prompt]);
      String rawText = response.text ?? "{}";
      rawText = rawText.replaceAll(RegExp(r'^```json'), '').replaceAll(RegExp(r'```$'), '').trim();

      dynamic decodedJSON;
      try { decodedJSON = jsonDecode(rawText); } catch (e) { return ExtractedInfo(content: "AI Error", isAnalyzed: false); }

      Map<String, dynamic> data = {};
      if (decodedJSON is List && decodedJSON.isNotEmpty) data = decodedJSON.first;
      else if (decodedJSON is Map<String, dynamic>) data = decodedJSON;

      RequestType type = RequestType.CUSTOM;
      String typeStr = data['request_type']?.toString() ?? "CUSTOM";
      for (var val in RequestType.values) { if (val.name == typeStr) type = val; }

      int pCount = 1;
      if (data['people_count'] is int) pCount = data['people_count'];
      else if (data['people_count'] is String) pCount = int.tryParse(data['people_count']) ?? 1;

      return ExtractedInfo(
        phoneNumbers: List<String>.from(data['phone_numbers'] ?? [senderPhone]),
        content: data['content'] ?? smsBody,
        peopleCount: pCount,
        address: data['address'] ?? "Unknown",
        requestType: type,
        isAnalyzed: true,
      );
    } catch (e) {
      debugPrint("Gemini Error: $e");
      bool isRateLimit = e.toString().contains("429") || e.toString().contains("Resource exhausted");
      return ExtractedInfo(
        phoneNumbers: [senderPhone],
        content: isRateLimit ? "Server busy. Retrying..." : "Analysis Failed",
        isAnalyzed: false,
        needsRetry: isRateLimit,
      );
    }
  }
}