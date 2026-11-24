import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_generator/features/finance/balance_math.dart';
import 'package:receipt_generator/features/finance/legacy_balance_resolver.dart';

// Receipt codes: Z = 2026, K = November, q = 17th. ZKq01 = first sale on 17 Nov.
int m(num naira) => (naira * 100).round();

LegacyReceiptRecord sale(
  String code,
  DateTime at, {
  num total = 10000,
  num deposit = 4000,
  String customer = 'Ada',
  String phone = '+2348011111111',
  List<String> items = const ['Banner'],
  String coupon = '',
}) =>
    LegacyReceiptRecord(
      code: code,
      issuedAt: at,
      customerName: customer,
      customerWhatsapp: phone,
      itemNames: items,
      couponReference: coupon,
      totalMinor: m(total),
      depositMinor: m(deposit),
    );

LegacyReceiptRecord phase5(String code, String linked, DateTime at, num amount) =>
    LegacyReceiptRecord(
      code: code,
      issuedAt: at,
      isBalanceType: true,
      linkedCode: linked,
      totalMinor: m(amount),
      depositMinor: m(amount),
    );

LegacyBalanceEntry entryOf(LegacyResolution r, String code) =>
    r.entries.firstWhere((e) => e.code == code);

LegacyResolution run(List<LegacyReceiptRecord> rs,
        [List<ManualLinkRecord> links = const []]) =>
    LegacyBalanceResolver.resolve(receipts: rs, manualLinks: links);

void main() {
  final d17 = DateTime(2026, 11, 17, 10);
  final d18 = DateTime(2026, 11, 18, 10);
  final d19 = DateTime(2026, 11, 19, 10);
  final d20 = DateTime(2026, 11, 20, 10);

  group('clean match', () {
    test('exact code with balance wording links automatically', () {
      final r = run([
        sale('ZKq01', d17), // owes 6000
        sale('ZKr01', d18,
            total: 6000, deposit: 6000, items: ['Balance for ZKq01']),
      ]);
      final e = entryOf(r, 'ZKr01');
      expect(e.status, LegacyStatus.linkedAuto);
      expect(e.originalCode, 'ZKq01');
      expect(e.appliedMinor, m(6000));
      expect(r.needsReviewCount, 0);
      expect(r.payments.length, 1);
      expect(r.payments.first.linkedCode, 'ZKq01');
    });

    test('normal sales are not treated as balance receipts', () {
      final r = run([sale('ZKq01', d17), sale('ZKr01', d18)]);
      expect(r.entries, isEmpty);
    });

    test('phase 5 balance receipts are ignored', () {
      final r = run([
        sale('ZKq01', d17),
        phase5('ZKr01-B', 'ZKq01', d18, 6000),
      ]);
      expect(r.entries, isEmpty);
    });

    test('code in the coupon field is read too', () {
      final r = run([
        sale('ZKq01', d17),
        sale('ZKr01', d18,
            total: 2000, deposit: 2000, items: ['Balance'], coupon: 'ZKq01'),
      ]);
      expect(entryOf(r, 'ZKr01').status, LegacyStatus.linkedAuto);
    });

    test('earlier phase 5 payments reduce what is left', () {
      final r = run([
        sale('ZKq01', d17), // owes 6000
        phase5('ZKr01-B', 'ZKq01', d18, 4000), // 2000 left
        sale('ZKs01', d19,
            total: 2000, deposit: 2000, items: ['Balance ZKq01']),
      ]);
      expect(entryOf(r, 'ZKs01').status, LegacyStatus.linkedAuto);
    });
  });

  group('typos and missing numbers', () {
    test('one wrong character is a suggestion, never auto-linked', () {
      final r = run([
        sale('ZKq01', d17),
        sale('ZKr01', d18,
            total: 6000, deposit: 6000, items: ['Balance ZKq02']),
      ]);
      final e = entryOf(r, 'ZKr01');
      expect(e.status, LegacyStatus.needsReview);
      expect(e.reason, ReviewReason.notFound);
      expect(e.suggestions.first.code, 'ZKq01');
    });

    test('capitals are case-sensitive: lowercase typed code is a suggestion', () {
      final r = run([
        sale('ZKq01', d17),
        sale('ZKr01', d18,
            total: 6000, deposit: 6000, items: ['balance zkq01']),
      ]);
      final e = entryOf(r, 'ZKr01');
      expect(e.status, LegacyStatus.needsReview);
      expect(e.suggestions.first.code, 'ZKq01');
      expect(e.suggestions.first.reasons.first, 'Same letters, different capitals');
    });

    test('no number at all: suggests same customer with balance owed', () {
      final r = run([
        sale('ZKq01', d17, customer: 'Ada'),
        sale('ZKq02', d17, customer: 'Bola', total: 9000, deposit: 1000),
        sale('ZKr01', d18,
            total: 6000, deposit: 6000, customer: 'Ada', items: ['Balance']),
      ]);
      final e = entryOf(r, 'ZKr01');
      expect(e.reason, ReviewReason.noReference);
      expect(e.suggestions.first.code, 'ZKq01');
    });

    test('a suggestion is never a sale dated after the balance receipt', () {
      final r = run([
        sale('ZKs01', d19, customer: 'Ada'),
        sale('ZKr01', d18,
            total: 6000, deposit: 6000, customer: 'Ada', items: ['Balance']),
      ]);
      expect(entryOf(r, 'ZKr01').suggestions, isEmpty);
    });
  });

  group('ambiguous', () {
    test('two different numbers are listed, not guessed', () {
      final r = run([
        sale('ZKq01', d17),
        sale('ZKq02', d17),
        sale('ZKr01', d18,
            total: 3000, deposit: 3000, items: ['Balance ZKq01 and ZKq02']),
      ]);
      final e = entryOf(r, 'ZKr01');
      expect(e.reason, ReviewReason.multipleReferences);
      expect(e.suggestions.map((s) => s.code), containsAll(['ZKq01', 'ZKq02']));
    });

    test('a number that points back at itself is listed', () {
      final r = run([
        sale('ZKr01', d18, total: 3000, deposit: 3000, items: ['Balance ZKr01']),
      ]);
      expect(entryOf(r, 'ZKr01').reason, ReviewReason.selfReference);
    });
  });

  group('chains', () {
    test('a balance that names an earlier balance resolves to the sale', () {
      final r = run([
        sale('ZKq01', d17), // owes 6000
        sale('ZKr01', d18,
            total: 2000, deposit: 2000, items: ['Balance ZKq01']),
        sale('ZKs01', d19,
            total: 3000, deposit: 3000, items: ['Balance ZKr01']),
      ]);
      expect(entryOf(r, 'ZKr01').originalCode, 'ZKq01');
      final last = entryOf(r, 'ZKs01');
      expect(last.status, LegacyStatus.linkedAuto);
      expect(last.originalCode, 'ZKq01');
      expect(r.payments.fold<int>(0, (a, p) => a + p.amountMinor), m(5000));
    });

    test('a chain through an unresolved receipt is listed', () {
      final r = run([
        sale('ZKq01', d17),
        sale('ZKr01', d18, total: 2000, deposit: 2000, items: ['Balance']),
        sale('ZKs01', d19,
            total: 3000, deposit: 3000, items: ['Balance ZKr01']),
      ]);
      expect(entryOf(r, 'ZKr01').status, LegacyStatus.needsReview);
      expect(entryOf(r, 'ZKs01').reason, ReviewReason.brokenChain);
    });

    test('a loop does not hang and is listed', () {
      final r = run([
        sale('ZKr01', d18, total: 1000, deposit: 1000, items: ['Balance ZKs01']),
        sale('ZKs01', d19, total: 1000, deposit: 1000, items: ['Balance ZKr01']),
      ]);
      expect(r.needsReviewCount, 2);
    });

    test('a legacy balance can point at a phase 5 balance receipt', () {
      final r = run([
        sale('ZKq01', d17),
        phase5('ZKr01-B', 'ZKq01', d18, 1000),
        sale('ZKs01', d19,
            total: 2000, deposit: 2000, items: ['Balance ZKr01-B']),
      ]);
      expect(entryOf(r, 'ZKs01').originalCode, 'ZKq01');
    });
  });

  group('mixed receipts', () {
    test('balance plus new items needs a manager amount', () {
      final r = run([
        sale('ZKq01', d17),
        sale('ZKr01', d18,
            total: 9000,
            deposit: 9000,
            items: ['Balance ZKq01', 'Business cards']),
      ]);
      final e = entryOf(r, 'ZKr01');
      expect(e.status, LegacyStatus.needsReview);
      expect(e.reason, ReviewReason.mixedReceipt);
      expect(e.originalCode, 'ZKq01'); // known, only the amount is missing
    });

    test('manual link with an amount settles a mixed receipt', () {
      final rs = [
        sale('ZKq01', d17),
        sale('ZKr01', d18,
            total: 9000,
            deposit: 9000,
            items: ['Balance ZKq01', 'Business cards']),
      ];
      final r = run(rs, [
        ManualLinkRecord(
            id: 'l1',
            receiptCode: 'ZKr01',
            originalCode: 'ZKq01',
            appliedMinor: m(6000)),
      ]);
      final e = entryOf(r, 'ZKr01');
      expect(e.status, LegacyStatus.linkedManual);
      expect(e.appliedMinor, m(6000));
      expect(r.needsReviewCount, 0);
    });
  });

  group('amounts', () {
    test('paying more than is owed is listed with the remaining balance', () {
      final r = run([
        sale('ZKq01', d17), // owes 6000
        sale('ZKr01', d18,
            total: 8000, deposit: 8000, items: ['Balance ZKq01']),
      ]);
      final e = entryOf(r, 'ZKr01');
      expect(e.reason, ReviewReason.exceedsBalance);
      expect(e.suggestedAppliedMinor, m(6000));
    });

    test('two payments that together exceed the balance: the later is listed', () {
      final r = run([
        sale('ZKq01', d17), // owes 6000
        sale('ZKr01', d18, total: 4000, deposit: 4000, items: ['Balance ZKq01']),
        sale('ZKs01', d19, total: 4000, deposit: 4000, items: ['Balance ZKq01']),
      ]);
      expect(entryOf(r, 'ZKr01').status, LegacyStatus.linkedAuto);
      final e = entryOf(r, 'ZKs01');
      expect(e.reason, ReviewReason.exceedsBalance);
      expect(e.suggestedAppliedMinor, m(2000));
    });

    test('no money received is listed', () {
      final r = run([
        sale('ZKq01', d17),
        sale('ZKr01', d18, total: 3000, deposit: 0, items: ['Balance ZKq01']),
      ]);
      expect(entryOf(r, 'ZKr01').reason, ReviewReason.noAmount);
    });
  });

  group('manual link check', () {
    final rs = [
      sale('ZKq01', d17), // owes 6000
      sale('ZKq02', d17, total: 5000, deposit: 5000), // paid in full
      sale('ZKr01', d18, total: 6000, deposit: 6000, items: ['Balance']),
      sale('ZKs01', d20), // dated after
    ];

    String? check(String original, num amount) =>
        LegacyBalanceResolver.validateManualLink(
          receipts: rs,
          manualLinks: const [],
          legacyCode: 'ZKr01',
          originalCode: original,
          appliedMinor: m(amount),
        );

    test('accepts a good link', () => expect(check('ZKq01', 6000), isNull));
    test('unknown number', () => expect(check('ZKq99', 100), isNotNull));
    test('itself', () => expect(check('ZKr01', 100), isNotNull));
    test('settled sale', () => expect(check('ZKq02', 100), isNotNull));
    test('sale dated later', () => expect(check('ZKs01', 100), isNotNull));
    test('more than owed', () => expect(check('ZKq01', 6001), isNotNull));
    test('more than received', () => expect(check('ZKq01', 7000), isNotNull));
    test('zero', () => expect(check('ZKq01', 0), isNotNull));
  });

  test('manual link overrides a wrong automatic match', () {
    final rs = [
      sale('ZKq01', d17),
      sale('ZKq02', d17, customer: 'Bola'),
      sale('ZKr01', d18,
          total: 3000, deposit: 3000, items: ['Balance ZKq01']),
    ];
    final auto = run(rs);
    expect(entryOf(auto, 'ZKr01').originalCode, 'ZKq01');
    final fixed = run(rs, [
      ManualLinkRecord(
          id: 'l1',
          receiptCode: 'ZKr01',
          originalCode: 'ZKq02',
          appliedMinor: m(3000)),
    ]);
    expect(entryOf(fixed, 'ZKr01').originalCode, 'ZKq02');
    expect(entryOf(fixed, 'ZKr01').status, LegacyStatus.linkedManual);
  });

  group('feeds the cashier balance maths', () {
    // Same steps BalanceRepository.outstandingByCode takes.
    Map<String, int> outstanding(List<LegacyReceiptRecord> rs) {
      final res = run(rs);
      final map = BalanceMath.outstandingBySale([
        for (final r in rs)
          if (!r.isBalanceType)
            SaleSummary(
                code: r.code,
                totalMinor: r.totalMinor,
                depositMinor: r.depositMinor),
      ], res.payments);
      for (final c in res.ownBalanceCleared) {
        if (map.containsKey(c)) map[c] = 0;
      }
      return map;
    }

    test('a linked payment reduces what the original owes', () {
      final o = outstanding([
        sale('ZKq01', d17), // owes 6000
        sale('ZKr01', d18, total: 4000, deposit: 4000, items: ['Balance ZKq01']),
      ]);
      expect(o['ZKq01'], m(2000));
      expect(o['ZKr01'], 0);
    });

    test('an under-paid pure balance receipt is not a second debt', () {
      final o = outstanding([
        sale('ZKq01', d17), // owes 6000
        sale('ZKr01', d18, total: 6000, deposit: 4000, items: ['Balance ZKq01']),
      ]);
      expect(o['ZKq01'], m(2000)); // only 4000 was received
      expect(o['ZKr01'], 0); // not owed twice
    });

    test('a mixed receipt keeps its own unpaid part', () {
      final rs = [
        sale('ZKq01', d17), // owes 6000
        sale('ZKr01', d18,
            total: 9000, deposit: 7000, items: ['Balance ZKq01', 'Cards']),
      ];
      final res = run(rs, [
        ManualLinkRecord(
            id: 'l1',
            receiptCode: 'ZKr01',
            originalCode: 'ZKq01',
            appliedMinor: m(6000)),
      ]);
      expect(entryOf(res, 'ZKr01').isMixed, isTrue);
      expect(res.ownBalanceCleared, isEmpty);
    });

    test('a linked receipt cannot be used as an original sale', () {
      final res = run([
        sale('ZKq01', d17),
        sale('ZKr01', d18, total: 4000, deposit: 4000, items: ['Balance ZKq01']),
      ]);
      expect(res.linkedCodes.contains('ZKr01'), isTrue);
      expect(res.linkedCodes.contains('ZKq01'), isFalse);
    });
  });

  group('number typed with no balance wording', () {
    test('an item that is just the original number links automatically', () {
      final r = run([
        sale('ZKx01', d17, total: 10000, deposit: 4000), // owes 6000
        sale('ZKx02', d18, total: 6000, deposit: 6000, items: ['ZKx01']),
      ]);
      final e = entryOf(r, 'ZKx02');
      expect(e.status, LegacyStatus.linkedAuto);
      expect(e.originalCode, 'ZKx01');
      expect(e.appliedMinor, m(6000));
    });

    test('a short prefix such as Item-ZKx01 still counts', () {
      final r = run([
        sale('ZKx01', d17),
        sale('ZKx02', d18, total: 6000, deposit: 6000, items: ['Item-ZKx01']),
      ]);
      expect(entryOf(r, 'ZKx02').status, LegacyStatus.linkedAuto);
    });

    test('a sentence that merely mentions a number is not a balance', () {
      final r = run([
        sale('ZKx01', d17),
        sale('ZKx02', d18, items: ['Reprint of banner from ZKx01']),
      ]);
      expect(r.entries, isEmpty);
    });

    test('a bare number that matches no receipt is ignored', () {
      final r = run([
        sale('ZKx01', d17),
        sale('ZKx02', d18, items: ['ZKx09']),
      ]);
      expect(r.entries, isEmpty);
    });
  });
}
