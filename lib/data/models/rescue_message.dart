import 'package:telephony/telephony.dart';
import 'extracted_info.dart';

class RescueMessage {
  final SmsMessage originalMessage;
  ExtractedInfo info; 
  bool isSos;
  bool apiSent;
  bool isAnalyzing; 

  RescueMessage({
    required this.originalMessage, 
    required this.info, 
    required this.isSos, 
    this.apiSent = false,
    this.isAnalyzing = false,
  });
}