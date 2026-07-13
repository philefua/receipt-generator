class DiscountCodeUtil {
  DiscountCodeUtil._();

  static const int _yearAnchor = 2026;
  static const int _maxSupportedYear = 2051;

  static String generateYearCode(int year) {
    final int index = (_yearAnchor + 25) - year;
    if (index < 0 || index > 25) {
      throw ArgumentError(
        'Year $year is outside the supported range ($_yearAnchor-$_maxSupportedYear).',
      );
    }
    return String.fromCharCode(0x41 + index);
  }

  static String generateMonthCode(int month) {
    if (month < 1 || month > 12) {
      throw ArgumentError('Month must be between 1 and 12, got $month.');
    }
    return String.fromCharCode(0x41 + (month - 1));
  }

  static String generateDayCode(int day) {
    if (day < 1 || day > 31) {
      throw ArgumentError('Day must be between 1 and 31, got $day.');
    }
    if (day <= 26) {
      return String.fromCharCode(0x61 + (day - 1));
    }
    return String.fromCharCode(0x41 + (day - 27));
  }

  static String generateSerial(int dailyOrderNumber) {
    if (dailyOrderNumber < 1 || dailyOrderNumber > 99) {
      throw ArgumentError(
        'Daily order counter must be between 1 and 99, got $dailyOrderNumber.',
      );
    }
    return dailyOrderNumber.toString().padLeft(2, '0');
  }

  static String generateReceiptCode({
    required DateTime date,
    required int dailyOrderNumber,
  }) {
    return generateYearCode(date.year) +
        generateMonthCode(date.month) +
        generateDayCode(date.day) +
        generateSerial(dailyOrderNumber);
  }
}
