import 'package:telephony/telephony.dart';
import 'extracted_info.dart';

class RescueMessage {
  final SmsMessage originalMessage;
  final String sender;
  final ExtractedInfo info;
  final bool isSos;
  final bool apiSent;
  final bool isAnalyzing;
  // NEW: Track if user manually edited this
  final bool hasManualOverride; 

  RescueMessage({
    required this.originalMessage,
    required this.sender,
    required this.info,
    required this.isSos,
    this.apiSent = false,
    this.isAnalyzing = false,
    this.hasManualOverride = false, // Default false
  });

  RescueMessage copyWith({
    ExtractedInfo? info,
    bool? isSos,
    bool? apiSent,
    bool? isAnalyzing,
    bool? hasManualOverride,
  }) {
    return RescueMessage(
      originalMessage: originalMessage,
      sender: sender,
      info: info ?? this.info,
      isSos: isSos ?? this.isSos,
      apiSent: apiSent ?? this.apiSent,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      hasManualOverride: hasManualOverride ?? this.hasManualOverride,
    );
  }
}