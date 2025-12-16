import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../../core/constants.dart';
import '../models/extracted_info.dart';
import '../models/request_type.dart';

class GeminiService {
  Future<ExtractedInfo> analyze(String text, String phone, String apiKey) async {
    if (apiKey.isEmpty) {
      return ExtractedInfo(phoneNumbers: [phone], isAnalyzed: false);
    }

    try {
      final model = GenerativeModel(
        model: AppConstants.defaultGeminiModel,
        apiKey: apiKey,
        generationConfig: GenerationConfig(responseMimeType: "application/json", temperature: 0.1),
      );

      final prompt = Content.text('''
        Bạn là hệ thống AI cứu hộ khẩn cấp. Input: Sender: $phone, Message: "$text".
        Nhiệm vụ: Trích xuất thông tin cứu hộ.
        Yêu cầu Output JSON:
        1. "phone_numbers": Danh sách số điện thoại liên hệ.
        2. "content": Trích xuất NỘI DUNG CẦN GIÚP ĐỠ cụ thể.
        3. "people_count": Số lượng người (Int).
        4. "address": Địa chỉ cụ thể.
        5. "request_type": Phân loại (URGENT_HOSPITAL, SAFE_PLACE, SUPPLIES, MEDICAL, CLOTHES, CUSTOM).
        
        Trả về JSON duy nhất: { "phone_numbers": [], "content": "", "people_count": 1, "address": "", "request_type": "CUSTOM" }
      ''');

      final response = await model.generateContent([prompt]);
      String raw = response.text?.replaceAll(RegExp(r'^```json|```$'), '').trim() ?? "{}";
      
      final data = jsonDecode(raw);
      final map = (data is List) ? data.first : data;

      RequestType type = RequestType.CUSTOM;
      for (var v in RequestType.values) if (v.name == map['request_type']) type = v;

      return ExtractedInfo(
        phoneNumbers: List<String>.from(map['phone_numbers'] ?? [phone]),
        content: map['content'] ?? "",
        peopleCount: int.tryParse(map['people_count'].toString()) ?? 1,
        address: map['address'] ?? "",
        lat: 0.0, // AI doesn't get coords, user adds them via Map Picker
        lng: 0.0,
        requestType: type,
        isAnalyzed: true,
      );
    } catch (e) {
      bool isRateLimit = e.toString().contains("429") || e.toString().contains("Resource exhausted");
      return ExtractedInfo(
        phoneNumbers: [phone],
        content: isRateLimit ? "Server busy..." : "",
        isAnalyzed: false,
        needsRetry: isRateLimit
      );
    }
  }
}