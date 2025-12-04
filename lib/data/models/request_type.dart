enum RequestType {
  URGENT_HOSPITAL, 
  SAFE_PLACE, 
  SUPPLIES, 
  MEDICAL, 
  CLOTHES, 
  CUSTOM
}

extension RequestTypeExt on RequestType {
  String get vietnameseName {
    switch (this) {
      case RequestType.URGENT_HOSPITAL: return "Đi viện gấp";
      case RequestType.SAFE_PLACE: return "Đến nơi an toàn";
      case RequestType.SUPPLIES: return "Nhu yếu phẩm";
      case RequestType.MEDICAL: return "Thiết bị y tế";
      case RequestType.CLOTHES: return "Quần áo";
      case RequestType.CUSTOM: return "Tự viết yêu cầu riêng";
    }
  }
}