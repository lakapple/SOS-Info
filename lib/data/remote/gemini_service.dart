import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../core/constants.dart';
import '../models/extracted_info.dart';
import '../models/request_type.dart';
import '../local/prefs_helper.dart';

class GeminiService {
  static Future<ExtractedInfo> extractData(String smsBody, String senderPhone) async {
    try {
      String apiKey = await PrefsHelper.getApiKey();
      if (apiKey.isEmpty) {
        return ExtractedInfo(content: "Error: No API Key in Settings", isAnalyzed: false);
      }

      final model = GenerativeModel(
        model: AppConstants.geminiModel,
        apiKey: apiKey,
        generationConfig: GenerationConfig(responseMimeType: "application/json", temperature: 0.1),
      );

      final prompt = Content.text('''
        Bạn là hệ thống AI cứu hộ. Input: Sender: $senderPhone, Message: "$smsBody".

        Nhiệm vụ: Trích xuất thông tin.
        Yêu cầu Output JSON:
        1. "phone_numbers": Danh sách số điện thoại tìm thấy.
        2. "content": Trích xuất NỘI DUNG CẦN GIÚP ĐỠ cụ thể (ví dụ: "cần đồ ăn, nước sạch", "nhà sập"). Bỏ qua lời chào.
        3. "people_count": Số lượng người (Int).
        4. "address": Địa chỉ.
        5. "request_type": Phân loại (URGENT_HOSPITAL, SAFE_PLACE, SUPPLIES, MEDICAL, CLOTHES, CUSTOM).
        
        JSON duy nhất: { "phone_numbers": [], "content": "", "people_count": 1, "address": "", "request_type": "CUSTOM" }
      ''');

      final response = await model.generateContent([prompt]);
      String rawText = response.text ?? "{}";
      rawText = rawText.replaceAll(RegExp(r'^```json'), '').replaceAll(RegExp(r'```$'), '').trim();

      dynamic decodedJSON;
      try { decodedJSON = jsonDecode(rawText); } catch (e) { return ExtractedInfo(content: "AI Error"); }

      Map<String, dynamic> data = (decodedJSON is List && decodedJSON.isNotEmpty) ? decodedJSON.first : decodedJSON;

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
      bool isRateLimit = e.toString().contains("429") || e.toString().contains("Resource exhausted");
      return ExtractedInfo(
        phoneNumbers: [senderPhone],
        content: isRateLimit ? "Server busy. Retrying..." : "Analysis Failed",
        needsRetry: isRateLimit,
      );
    }
  }
}