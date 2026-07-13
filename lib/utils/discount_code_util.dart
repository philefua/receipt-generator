class DiscountCodeUtil {
  static String generateReceiptCode(int orderSerialNumber) {
    final now = DateTime.now();
    
    // 1. Year: 2026 = Z, 2027 = Y, 2028 = X, etc.
    int yearDiff = now.year - 2026;
    String yearChar = String.fromCharCode(90 - yearDiff); // 90 is 'Z'
    
    // 2. Month: Jan = A, Feb = B ... Dec = L
    String monthChar = String.fromCharCode(65 + (now.month - 1)); // 65 is 'A'
    
    // 3. Day: 1-26 = a-z, 27-31 = A-E
    String dayChar;
    if (now.day <= 26) {
      dayChar = String.fromCharCode(97 + (now.day - 1)); // 97 is 'a'
    } else {
      dayChar = String.fromCharCode(65 + (now.day - 27)); // 65 is 'A'
    }
    
    // 4. Serial: 2-digit zero-padded
    String serialStr = orderSerialNumber.toString().padLeft(2, '0');
    
    return '$yearChar$monthChar$dayChar$serialStr';
  }
}
