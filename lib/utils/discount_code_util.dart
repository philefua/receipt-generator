/// Generates the immutable, deterministic receipt serial code.
///
/// Format: [Year][Month][Day][Serial]  e.g. "ZAe09"
///
/// YEAR   -> Uppercase A-Z, DESCENDING from 2026 == 'Z'
///           (2026=Z, 2027=Y, 2028=X, ... valid through 2051=A)
/// MONTH  -> Uppercase A-L, ASCENDING (Jan=A ... Dec=L)
/// DAY    -> lowercase a-z for days 1-26 (1st=a ... 26th=z)
///           uppercase A-E for days 27-31 (27th=A ... 31st=E)
/// SERIAL -> 2-digit zero-padded daily order counter (01-99)
class DiscountCodeUtil {
  DiscountCodeUtil._(); // static-only utility, no instances

  static const int _yearAnchor = 2026; // 2026 maps to 'Z' (index 25)
  static const int _maxSupportedYear = 2051; // index 0 -> 'A'

  /// Year code: descending mapping, 2026 = Z.
  static String generateYearCode(int year) {
    final int index = (_yearAnchor + 25) - year; // 2051 - year
    if (index < 0 || index > 25) {
      throw ArgumentError(
        'Year $year is outside the supported range ($_yearAnchor-$_maxSupportedYear).',
      );
    }
    return String.fromCharCode(0x41 + index); // 'A' + index
  }

  /// Month code: ascending mapping, Jan = A, Dec = L.
  static String generateMonthCode(int month) {
    if (month < 1 || month > 12) {
      throw ArgumentError('Month must be between 1 and 12, got $month.');
    }
    return String.fromCharCode(0x41 + (month - 1));
  }

  /// Day code: lowercase a-z for 1-26, uppercase A-E for 27-31.
  static String generateDayCode(int day) {
    if (day < 1 || day > 31) {
      throw ArgumentError('Day must be between 1 and 31, got $day.');
    }
    if (day <= 26) {
      return String.fromCharCode(0x61 + (day - 1)); // 'a' + (day-1)
    }
    return String.fromCharCode(0x41 + (day - 27)); // 'A' + (day-27)
  }

  /// Serial code: 2-digit zero-padded daily order counter (1-99).
  static String generateSerial(int dailyOrderNumber) {
    if (dailyOrderNumber < 1 || dailyOrderNumber > 99) {
      throw ArgumentError(
        'Daily order counter must be between 1 and 99, got $dailyOrderNumber.',
      );
    }
    return dailyOrderNumber.toString().padLeft(2, '0');
  }

  /// Full composed receipt serial code.
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