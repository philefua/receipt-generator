import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_generator/utils/discount_code_util.dart';

void main() {
  group('DiscountCodeUtil - spec validation', () {
    test('9th order on Jan 5, 2026 -> "ZAe09"', () {
      final code = DiscountCodeUtil.generateReceiptCode(
        date: DateTime(2026, 1, 5),
        dailyOrderNumber: 9,
      );
      expect(code, equals('ZAe09'));
    });

    test('23rd order on Dec 30, 2028 -> "XLD23"', () {
      final code = DiscountCodeUtil.generateReceiptCode(
        date: DateTime(2028, 12, 30),
        dailyOrderNumber: 23,
      );
      expect(code, equals('XLD23'));
    });

    test('Year mapping is descending from 2026', () {
      expect(DiscountCodeUtil.generateYearCode(2026), 'Z');
      expect(DiscountCodeUtil.generateYearCode(2027), 'Y');
      expect(DiscountCodeUtil.generateYearCode(2028), 'X');
    });

    test('Month mapping: Jan=A, Dec=L', () {
      expect(DiscountCodeUtil.generateMonthCode(1), 'A');
      expect(DiscountCodeUtil.generateMonthCode(12), 'L');
    });

    test('Day mapping boundaries: 1=a, 26=z, 27=A, 31=E', () {
      expect(DiscountCodeUtil.generateDayCode(1), 'a');
      expect(DiscountCodeUtil.generateDayCode(26), 'z');
      expect(DiscountCodeUtil.generateDayCode(27), 'A');
      expect(DiscountCodeUtil.generateDayCode(31), 'E');
    });

    test('Serial is always 2 digits', () {
      expect(DiscountCodeUtil.generateSerial(1), '01');
      expect(DiscountCodeUtil.generateSerial(99), '99');
    });

    test('Throws on out-of-range inputs', () {
      expect(() => DiscountCodeUtil.generateMonthCode(13), throwsArgumentError);
      expect(() => DiscountCodeUtil.generateDayCode(32), throwsArgumentError);
      expect(() => DiscountCodeUtil.generateSerial(100), throwsArgumentError);
      expect(() => DiscountCodeUtil.generateSerial(0), throwsArgumentError);
    });
  });
}