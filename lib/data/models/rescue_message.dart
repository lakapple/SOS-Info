import 'package:telephony/telephony.dart';
import 'extracted_info.dart';

class RescueMessage {
  final SmsMessage originalMessage;
  final String sender; // NEW: The sanitized phone number (0xxxx)
  ExtractedInfo info; 
  bool isSos;
  bool apiSent;
  bool isAnalyzing; 

  RescueMessage({
    required this.originalMessage,
    required this.sender, // Require this in constructor
    required this.info, 
    required this.isSos, 
    this.apiSent = false,
    this.isAnalyzing = false,
  });
}