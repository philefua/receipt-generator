import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_generator/features/finance/legacy_balance_resolver.dart';
import 'package:receipt_generator/features/finance/writeoff_math.dart';

int m(num naira) => (naira * 100).round();

String? check({
  bool isSale = true,
  num owed = 1000,
  num amount = 100,
  String reason = 'Customer paid less',
}) =>
    WriteoffMath.validate(
      isSale: isSale,
      outstandingMinor: m(owed),
      amountMinor: m(amount),
      reason: reason,
    );

LegacyReceiptRecord sale(String code, DateTime at,
        {num total = 10000, num deposit = 4000, List<String> items = const ['Banner']}) =>
    LegacyReceiptRecord(
      code: code,
      issuedAt: at,
      itemNames: items,
      totalMinor: m(total),
      depositMinor: m(deposit),
    );

void main() {
  group('write-off rules', () {
    test('accepts a good write-off', () => expect(check(), isNull));
    test('accepts writing off the whole balance',
        () => expect(check(amount: 1000), isNull));
    test('refuses a balance receipt', () => expect(check(isSale: false), isNotNull));
    test('refuses when nothing is owed', () => expect(check(owed: 0), isNotNull));
    test('refuses zero', () => expect(check(amount: 0), isNotNull));
    test('refuses more than owed', () => expect(check(amount: 1000.01), isNotNull));
    test('requires a reason', () => expect(check(reason: '   '), isNotNull));
  });

  group('write-offs and old balance links', () {
    final d17 = DateTime(2026, 11, 17, 10);
    final d18 = DateTime(2026, 11, 18, 10);

    test('a write-off lowers what an old balance receipt can be linked for', () {
      final rs = [
        sale('ZKq01', d17), // owes 6000
        sale('ZKr01', d18, total: 6000, deposit: 6000, items: ['ZKq01']),
      ];
      // 6000 owed, 1000 written off: only 5000 can still be paid.
      final res = LegacyBalanceResolver.resolve(
        receipts: rs,
        manualLinks: const [],
        writeoffs: {'ZKq01': m(1000)},
      );
      final e = res.entries.firstWhere((x) => x.code == 'ZKr01');
      expect(e.status, LegacyStatus.needsReview);
      expect(e.reason, ReviewReason.exceedsBalance);
      expect(e.suggestedAppliedMinor, m(5000));
    });

    test('without a write-off the same receipt links cleanly', () {
      final rs = [
        sale('ZKq01', d17),
        sale('ZKr01', d18, total: 6000, deposit: 6000, items: ['ZKq01']),
      ];
      final res = LegacyBalanceResolver.resolve(
          receipts: rs, manualLinks: const []);
      expect(res.entries.first.status, LegacyStatus.linkedAuto);
    });

    test('a manual link cannot exceed what is left after a write-off', () {
      final rs = [
        sale('ZKq01', d17),
        sale('ZKr01', d18, total: 6000, deposit: 6000, items: ['Balance']),
      ];
      final problem = LegacyBalanceResolver.validateManualLink(
        receipts: rs,
        manualLinks: const [],
        legacyCode: 'ZKr01',
        originalCode: 'ZKq01',
        appliedMinor: m(6000),
        writeoffs: {'ZKq01': m(1000)},
      );
      expect(problem, isNotNull);
    });
  });
}
