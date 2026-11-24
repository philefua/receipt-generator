import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_generator/features/finance/asset_rules.dart';
import 'package:receipt_generator/features/finance/depreciation.dart';

int m(num naira) => (naira * 100).round();

AssetSpec sl({
  DateTime? bought,
  num cost = 120000,
  num residual = 0,
  int life = 12,
  DateTime? retired,
  num proceeds = 0,
  bool voided = false,
}) =>
    AssetSpec(
      purchaseDate: bought ?? DateTime(2026, 1, 15),
      costMinor: m(cost),
      residualMinor: m(residual),
      usefulLifeMonths: life,
      retiredDate: retired,
      proceedsMinor: m(proceeds),
      voided: voided,
    );

AssetSpec rb({num cost = 100000, num residual = 0, double rate = 20}) =>
    AssetSpec(
      purchaseDate: DateTime(2026, 1, 15),
      costMinor: m(cost),
      residualMinor: m(residual),
      usefulLifeMonths: 60,
      reducingBalance: true,
      annualRatePercent: rate,
    );

void main() {
  group('straight line', () {
    test('first charge is the full month of purchase', () {
      final a = sl(); // 10,000 a month
      expect(Depreciation.accumulated(a, DateTime(2026, 1, 31)), m(10000));
    });

    test('nothing before the purchase month', () {
      expect(Depreciation.accumulated(sl(), DateTime(2025, 12, 31)), 0);
    });

    test('stops once cost less residual is reached', () {
      final a = sl();
      expect(Depreciation.accumulated(a, DateTime(2026, 12, 1)), m(120000));
      expect(Depreciation.accumulated(a, DateTime(2030, 6, 1)), m(120000));
    });

    test('odd amounts add up exactly, no rounding drift', () {
      final a = sl(cost: 10000, life: 3); // 3333.33, 3333.34, 3333.33
      final m1 = Depreciation.accumulated(a, DateTime(2026, 1, 1));
      final m2 = Depreciation.accumulated(a, DateTime(2026, 2, 1));
      final m3 = Depreciation.accumulated(a, DateTime(2026, 3, 1));
      expect(m1, 333333);
      expect(m2, 666667);
      expect(m3, m(10000));
    });

    test('residual value is kept', () {
      final a = sl(cost: 100000, residual: 10000, life: 36);
      expect(Depreciation.accumulated(a, DateTime(2030, 1, 1)), m(90000));
      expect(Depreciation.netBookValue(a, DateTime(2030, 1, 1)), m(10000));
    });

    test('charge for a period counts whole months, inclusive', () {
      final a = sl();
      expect(Depreciation.charge(a, DateTime(2026, 3, 1), DateTime(2026, 5, 31)),
          m(30000));
    });

    test('a period before the asset existed has no charge', () {
      expect(Depreciation.charge(sl(), DateTime(2025, 1, 1), DateTime(2025, 12, 31)), 0);
    });

    test('a period reversed has no charge', () {
      expect(Depreciation.charge(sl(), DateTime(2026, 5, 1), DateTime(2026, 3, 1)), 0);
    });

    test('equipment bought years ago is already fully depreciated', () {
      final a = sl(bought: DateTime(2023, 1, 10), cost: 360000, life: 36);
      expect(Depreciation.netBookValue(a, DateTime(2026, 11, 24)), 0);
      expect(Depreciation.charge(a, DateTime(2026, 1, 1), DateTime(2026, 12, 31)), 0);
    });

    test('equipment bought years ago still depreciating', () {
      final a = sl(bought: DateTime(2025, 1, 10), cost: 360000, life: 60); // 6,000 a month
      // Jan 2025 .. Nov 2026 = 23 months
      expect(Depreciation.accumulated(a, DateTime(2026, 11, 24)), m(138000));
      // Only 2026 so far: Jan..Nov = 11 months
      expect(Depreciation.charge(a, DateTime(2026, 1, 1), DateTime(2026, 11, 30)),
          m(66000));
    });
  });

  group('reducing balance', () {
    test('month one is cost x rate / 12', () {
      expect(Depreciation.accumulated(rb(), DateTime(2026, 1, 1)), 166667);
    });

    test('month two works on what is left', () {
      expect(Depreciation.accumulated(rb(), DateTime(2026, 2, 1)), 330556);
    });

    test('never goes below residual', () {
      final a = rb(cost: 1000, residual: 900, rate: 100);
      expect(Depreciation.accumulated(a, DateTime(2040, 1, 1)), m(100));
      expect(Depreciation.netBookValue(a, DateTime(2040, 1, 1)), m(900));
    });

    test('a zero rate never depreciates', () {
      expect(Depreciation.accumulated(rb(rate: 0), DateTime(2030, 1, 1)), 0);
    });
  });

  group('retirement', () {
    test('the retirement month is charged, later months are not', () {
      final a = sl(retired: DateTime(2026, 6, 20));
      expect(Depreciation.accumulated(a, DateTime(2026, 6, 30)), m(60000));
      expect(Depreciation.accumulated(a, DateTime(2026, 12, 31)), m(60000));
    });

    test('proceeds above book value are a gain', () {
      final d = Depreciation.disposal(
          sl(retired: DateTime(2026, 6, 20), proceeds: 70000))!;
      expect(d.nbvMinor, m(60000));
      expect(d.gainLossMinor, m(10000));
    });

    test('proceeds below book value are a loss', () {
      final d = Depreciation.disposal(
          sl(retired: DateTime(2026, 6, 20), proceeds: 20000))!;
      expect(d.gainLossMinor, -m(40000));
    });

    test('no proceeds is a write-off loss equal to book value', () {
      final d = Depreciation.disposal(sl(retired: DateTime(2026, 6, 20)))!;
      expect(d.gainLossMinor, -m(60000));
    });

    test('an asset that is not retired has no disposal', () {
      expect(Depreciation.disposal(sl()), isNull);
    });

    test('withRetirement previews a retirement', () {
      final d = Depreciation.disposal(
          sl().withRetirement(DateTime(2026, 3, 5), m(5000)))!;
      expect(d.nbvMinor, m(90000)); // 3 months charged
      expect(d.gainLossMinor, m(5000) - m(90000));
    });

    test('retired-within checks the retirement month', () {
      final a = sl(retired: DateTime(2026, 6, 20));
      expect(Depreciation.retiredWithin(a, DateTime(2026, 6, 1), DateTime(2026, 6, 30)), isTrue);
      expect(Depreciation.retiredWithin(a, DateTime(2026, 7, 1), DateTime(2026, 12, 31)), isFalse);
    });
  });

  test('totals leave out voided assets', () {
    final total = Depreciation.totalCharge([
      sl(),
      sl(voided: true),
    ], DateTime(2026, 1, 1), DateTime(2026, 1, 31));
    expect(total, m(10000));
  });

  group('form rules', () {
    final today = DateTime(2026, 11, 24);

    String? check({
      String name = 'Printer',
      DateTime? date,
      double cost = 100000,
      double residual = 0,
      int? life = 60,
      bool reducing = false,
      double? rate,
    }) =>
        AssetRules.validateNew(
          name: name,
          purchaseDate: date ?? DateTime(2026, 1, 1),
          today: today,
          cost: cost,
          residual: residual,
          usefulLifeMonths: life,
          reducingBalance: reducing,
          annualRatePercent: rate,
        );

    test('accepts a good asset', () => expect(check(), isNull));
    test('accepts a purchase date from years ago',
        () => expect(check(date: DateTime(2019, 3, 1)), isNull));
    test('refuses a future date',
        () => expect(check(date: DateTime(2026, 12, 1)), isNotNull));
    test('refuses an empty name', () => expect(check(name: ' '), isNotNull));
    test('refuses zero cost', () => expect(check(cost: 0), isNotNull));
    test('refuses residual at or above cost',
        () => expect(check(residual: 100000), isNotNull));
    test('refuses a missing life', () => expect(check(life: null), isNotNull));
    test('refuses zero life', () => expect(check(life: 0), isNotNull));
    test('reducing balance needs a rate',
        () => expect(check(reducing: true), isNotNull));
    test('reducing balance accepts a rate',
        () => expect(check(reducing: true, rate: 20), isNull));
    test('refuses a rate above 100',
        () => expect(check(reducing: true, rate: 150), isNotNull));

    test('retire: good', () {
      expect(
          AssetRules.validateRetire(
            isActive: true,
            isVoided: false,
            purchaseDate: DateTime(2026, 1, 1),
            retireDate: DateTime(2026, 6, 1),
            today: today,
            proceeds: 500,
          ),
          isNull);
    });
    test('retire: before purchase', () {
      expect(
          AssetRules.validateRetire(
            isActive: true,
            isVoided: false,
            purchaseDate: DateTime(2026, 6, 1),
            retireDate: DateTime(2026, 5, 1),
            today: today,
          ),
          isNotNull);
    });
    test('retire: already retired', () {
      expect(
          AssetRules.validateRetire(
            isActive: false,
            isVoided: false,
            purchaseDate: DateTime(2026, 1, 1),
            retireDate: DateTime(2026, 6, 1),
            today: today,
          ),
          isNotNull);
    });
    test('retire: negative proceeds', () {
      expect(
          AssetRules.validateRetire(
            isActive: true,
            isVoided: false,
            purchaseDate: DateTime(2026, 1, 1),
            retireDate: DateTime(2026, 6, 1),
            today: today,
            proceeds: -1,
          ),
          isNotNull);
    });
    test('void needs a reason',
        () => expect(AssetRules.validateVoid(reason: '', isVoided: false), isNotNull));
    test('void twice is refused',
        () => expect(AssetRules.validateVoid(reason: 'x', isVoided: true), isNotNull));

    test('threshold suggestion', () {
      expect(AssetRules.belowThreshold(cost: 5000, threshold: 20000, isOpeningBalance: false), isTrue);
      expect(AssetRules.belowThreshold(cost: 5000, threshold: 0, isOpeningBalance: false), isFalse);
      expect(AssetRules.belowThreshold(cost: 5000, threshold: 20000, isOpeningBalance: true), isFalse);
      expect(AssetRules.belowThreshold(cost: 25000, threshold: 20000, isOpeningBalance: false), isFalse);
    });
  });
}
