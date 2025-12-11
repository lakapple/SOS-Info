import 'package:telephony/telephony.dart';
import 'extracted_info.dart';

class RescueMessage {
  final SmsMessage originalMessage;
  final String sender; // Formatted Phone
  final ExtractedInfo info; 
  final bool isSos;
  final bool apiSent;
  final bool isAnalyzing; 

  RescueMessage({
    required this.originalMessage, 
    required this.sender,
    required this.info, 
    required this.isSos, 
    this.apiSent = false,
    this.isAnalyzing = false,
  });

  // Helper for Riverpod state updates (Immutability)
  RescueMessage copyWith({
    ExtractedInfo? info,
    bool? isSos,
    bool? apiSent,
    bool? isAnalyzing,
  }) {
    return RescueMessage(
      originalMessage: originalMessage,
      sender: sender,
      info: info ?? this.info,
      isSos: isSos ?? this.isSos,
      apiSent: apiSent ?? this.apiSent,
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
    );
  }
}