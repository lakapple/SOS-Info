class AppUtils {
  static String formatPhoneNumber(String phone) {
    String p = phone.replaceAll(RegExp(r'\s+'), '').trim();

    if (p.startsWith("+84")) {
      return "0${p.substring(3)}";
    }
    return p;
  }
}

