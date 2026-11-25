import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_generator/features/finance/depreciation.dart' as dep;
import 'package:receipt_generator/features/finance/legacy_balance_resolver.dart';
import 'package:receipt_generator/features/finance/loan_math.dart';
import 'package:receipt_generator/features/finance/report_data.dart';
import 'package:receipt_generator/features/finance/report_engine.dart';
import 'package:receipt_generator/features/finance/report_inputs.dart';
import 'package:receipt_generator/features/finance/report_period.dart';

import 'report_fixtures.dart';

// Fixed Assets, Loans, Filing Figures, Unmatched and Notes sheets, checked
// against the same hand-worked November 2026 shop as report_engine_test.dart.

ReportPeriod novPeriod() =>
    ReportPeriod.custom(DateTime(2026, 11, 1), DateTime(2026, 11, 30));

void main() {
  group('fixed assets sheet', () {
    final r = novReport();
    final f = r.fixedAssets;

    FixedAssetRow row(String name) => f.rows.firstWhere((x) => x.name == name);

    test('which assets are listed', () {
      // A7 is voided. Every other asset was on the register this month.
      expect(f.rows.map((x) => x.name).join(','), 'A3,A6,A2,A4,A5,A1');
    });

    test('bought this month: no depreciation yet at the start', () {
      final a = row('A1');
      expect(a.accumulatedAtStartMinor, 0);
      expect(a.chargeMinor, m(10000));
      expect(a.accumulatedAtEndMinor, m(10000));
      expect(a.netBookValueMinor, m(110000));
      expect(a.carryingMinor, m(110000));
    });

    test('reducing balance', () {
      final a = row('A2');
      expect(a.method, 'Reducing balance');
      expect(a.accumulatedAtStartMinor, 1547062);
      expect(a.chargeMinor, 140882);
      expect(a.accumulatedAtEndMinor, 1687944);
      expect(a.netBookValueMinor, 8312056);
    });

    test('fully depreciated asset has no charge and no book value', () {
      final a = row('A3');
      expect(a.accumulatedAtStartMinor, m(36000));
      expect(a.chargeMinor, 0);
      expect(a.netBookValueMinor, 0);
      expect(a.isOpeningBalance, isTrue);
    });

    test('retired this month: charged for November, carrying value is zero', () {
      final a = row('A4');
      expect(a.accumulatedAtStartMinor, m(10000));
      expect(a.chargeMinor, m(1000));
      expect(a.netBookValueMinor, m(49000)); // its book value when retired
      expect(a.carryingMinor, 0);
      expect(a.retiredInPeriod, isTrue);
    });

    test('owned before the app and still depreciating', () {
      final a = row('A6');
      expect(a.accumulatedAtStartMinor, m(22000));
      expect(a.chargeMinor, m(1000));
      expect(a.netBookValueMinor, m(37000));
    });

    test('start plus charge equals end for every asset', () {
      for (final a in f.rows) {
        expect(a.accumulatedAtStartMinor + a.chargeMinor, a.accumulatedAtEndMinor);
        expect(a.costMinor - a.accumulatedAtEndMinor, a.netBookValueMinor);
      }
    });

    test('additions and disposals', () {
      expect(f.additions.map((x) => x.name).join(','), 'A1');
      expect(f.additionsCashMinor, m(120000));
      expect(f.disposals.map((x) => x.name).join(','), 'A5,A4');
      final a4 = f.disposals.firstWhere((x) => x.name == 'A4');
      expect(a4.proceedsMinor, m(40000));
      expect(a4.nbvAtDisposalMinor, m(49000));
      expect(a4.gainLossMinor, -m(9000));
      final a5 = f.disposals.firstWhere((x) => x.name == 'A5');
      expect(a5.proceedsMinor, 0);
      expect(a5.gainLossMinor, -m(13000));
    });

    test('totals tie to the P&L, Cashflow and Summary', () {
      expect(f.chargeMinor, r.pnl.depreciationMinor);
      expect(f.disposalGainLossMinor, r.pnl.disposalGainLossMinor);
      expect(f.additionsCashMinor, r.cashflow.assetPurchasesMinor);
      expect(f.disposalProceedsMinor, r.cashflow.disposalProceedsMinor);
      expect(f.carryingMinor, r.summary.assetNetBookValueMinor);
      expect(f.accumulatedAtStartMinor + f.chargeMinor, f.accumulatedAtEndMinor);
      expect(f.costMinor - f.accumulatedAtEndMinor, f.netBookValueMinor);
    });

    test('totals', () {
      expect(f.costMinor, m(400000));
      expect(f.chargeMinor, 1440882);
      expect(f.carryingMinor, 23012056);
      expect(f.disposalProceedsMinor, m(40000));
      expect(f.disposalNbvMinor, m(62000));
    });

    test('an asset retired before the period is not listed', () {
      final rep = ReportEngine.generate(dataset(),
          ReportPeriod.custom(DateTime(2026, 12, 1), DateTime(2026, 12, 31)));
      // A4 and A5 were retired in November.
      expect(rep.fixedAssets.rows.map((x) => x.name).join(','), 'A3,A6,A2,A1');
      expect(rep.fixedAssets.disposals, isEmpty);
    });

    test('an asset bought after the period is not listed', () {
      final rep = ReportEngine.generate(dataset(),
          ReportPeriod.custom(DateTime(2026, 10, 1), DateTime(2026, 10, 31)));
      expect(rep.fixedAssets.rows.any((x) => x.name == 'A1'), isFalse);
    });

    test('equipment already owned is an addition but moves no cash', () {
      final input = ReportInput(assets: [
        asset(
            'Old press',
            AssetSpecForTest.bought(DateTime(2026, 11, 3), 50000, 50),
            opening: true),
      ]);
      final rep = novReport(input);
      expect(rep.fixedAssets.additions.length, 1);
      expect(rep.fixedAssets.additionsCostMinor, m(50000));
      expect(rep.fixedAssets.additionsCashMinor, 0);
      expect(rep.cashflow.assetPurchasesMinor, 0);
    });
  });

  group('loans sheet', () {
    final r = novReport();
    final l = r.loans;

    LoanRowData row(String lender) => l.rows.firstWhere((x) => x.lenderName == lender);

    test('which loans are listed', () {
      // The voided loan is left out.
      expect(l.rows.map((x) => x.lenderName).join(','), 'Bank,Cooperative');
    });

    test('a loan received this month', () {
      final x = row('Bank');
      expect(x.balanceAtStartMinor, 0);
      expect(x.receivedMinor, m(200000));
      expect(x.principalRepaidMinor, m(25000));
      expect(x.balanceAtEndMinor, m(175000));
      expect(x.interestPaidMinor, m(5000));
      expect(x.settled, isFalse);
    });

    test('a loan that already existed: balance from the start, nothing received', () {
      final x = row('Cooperative');
      expect(x.isOpeningBalance, isTrue);
      expect(x.balanceAtStartMinor, m(50000));
      expect(x.receivedMinor, 0);
      expect(x.principalRepaidMinor, m(10000));
      expect(x.balanceAtEndMinor, m(40000));
      expect(x.interestPaidMinor, m(2000));
    });

    test('repayments in the period, voided ones left out', () {
      expect(l.repayments.length, 3);
      expect(l.repayments.map((x) => x.lenderName).join(','),
          'Cooperative,Bank,Bank');
      expect(l.repayments.first.principalMinor, m(10000));
      expect(l.repayments.first.interestMinor, m(2000));
    });

    test('closing balance = opening + received - principal repaid', () {
      for (final x in l.rows) {
        expect(x.balanceAtEndMinor,
            x.balanceAtStartMinor + x.receivedMinor - x.principalRepaidMinor);
      }
      expect(l.balanceAtEndMinor,
          l.balanceAtStartMinor + l.receivedMinor - l.principalRepaidMinor);
    });

    test('totals tie to Cashflow, P&L and Summary', () {
      expect(l.receivedMinor, r.cashflow.loansReceivedMinor);
      expect(l.principalRepaidMinor, r.cashflow.principalRepaidMinor);
      expect(l.interestPaidMinor, r.cashflow.interestPaidMinor);
      expect(l.interestPaidMinor, r.pnl.interestPaidMinor);
      expect(l.balanceAtEndMinor, r.summary.loansOutstandingMinor);
      expect(l.repayments.fold<int>(0, (s, x) => s + x.interestMinor),
          l.interestPaidMinor);
    });

    test('a loan settled in the period', () {
      final input = ReportInput(
        loans: [
          ReportLoan(
              id: 'LN4',
              lenderName: 'Friend',
              spec: LoanSpec(
                  id: 'LN4',
                  dateReceived: DateTime(2026, 10, 5),
                  principalMinor: m(30000)),
              receivedInto: 'Cash'),
        ],
        repayments: [repay('LN4', nov(5), 30000, 500, 'Cash')],
      );
      final x = novReport(input).loans.rows.single;
      expect(x.balanceAtStartMinor, m(30000));
      expect(x.balanceAtEndMinor, 0);
      expect(x.settled, isTrue);
      expect(x.interestPaidMinor, m(500));
    });

    test('a loan settled before the period does not appear', () {
      final input = ReportInput(
        loans: [
          ReportLoan(
              id: 'LN5',
              lenderName: 'Old',
              spec: LoanSpec(
                  id: 'LN5',
                  dateReceived: DateTime(2026, 5, 5),
                  principalMinor: m(1000))),
        ],
        repayments: [repay('LN5', DateTime(2026, 6, 1), 1000, 0, 'Cash')],
      );
      expect(novReport(input).loans.rows, isEmpty);
    });

    test('loan money never reaches Sales, Expenses or the P&L operating lines', () {
      expect(r.sales.revenueMinor, m(149000));
      expect(r.expenses.totalMinor, m(24000));
      expect(r.pnl.operatingExpensesMinor, m(17500));
      // Without the loans and assets the operating figures do not change.
      final bare = novReport(ReportInput(
        settings: dataset().settings,
        receipts: dataset().receipts,
        expenses: dataset().expenses,
        writeoffs: dataset().writeoffs,
        legacy: dataset().legacy,
        stockCounts: dataset().stockCounts,
      ));
      expect(bare.sales.revenueMinor, r.sales.revenueMinor);
      expect(bare.expenses.totalMinor, r.expenses.totalMinor);
      expect(bare.pnl.grossProfitMinor, r.pnl.grossProfitMinor);
      expect(bare.pnl.operatingExpensesMinor, r.pnl.operatingExpensesMinor);
    });
  });

  group('filing figures', () {
    final r = novReport(dataset(vat: true));
    final f = r.filing;

    test('profit figures match the P&L', () {
      expect(f.turnoverMinor, m(149000));
      expect(f.directCostsMinor, m(5000));
      expect(f.operatingExpensesMinor, m(17500));
      expect(f.bookDepreciationMinor, 1440882);
      expect(f.interestPaidMinor, m(7000));
      expect(f.disposalGainLossMinor, -m(22000));
      expect(f.netProfitBeforeTaxMinor, 8209118);
      expect(f.estimatedTaxMinor, 2462735);
    });

    test('VAT collected is taken out of sales that already include it', () {
      // 149,000 x 7.5 / 107.5 = 10,395.35
      expect(f.vatEnabled, isTrue);
      expect(f.vatCollectedMinor, 1039535);
    });

    test('input VAT leaves out voided expenses', () {
      // 300 + 750. The voided expense carried 999.
      expect(f.inputVatPaidMinor, m(1050));
      expect(f.vatPayableMinor, 1039535 - m(1050));
    });

    test('balance sheet style figures', () {
      expect(f.receivablesMinor, m(10000));
      expect(f.closingStockMinor, m(4500));
      expect(f.assetNetBookValueMinor, 23012056);
      expect(f.loansOutstandingMinor, m(215000));
    });

    test('VAT lines are empty when VAT is off', () {
      final off = novReport().filing;
      expect(off.vatEnabled, isFalse);
      expect(off.vatCollectedMinor, isNull);
      expect(off.vatPayableMinor, isNull);
      // Input VAT noted on expenses is still shown.
      expect(off.inputVatPaidMinor, m(1050));
    });

    test('estimated tax is empty when no rate is set', () {
      expect(novReport(dataset(taxRate: 0)).filing.estimatedTaxMinor, isNull);
    });

    test('no stock count means no closing stock', () {
      final none = novReport(ReportInput(
        settings: dataset().settings,
        receipts: dataset().receipts,
      ));
      expect(none.filing.closingStockMinor, isNull);
    });

    test('the disclaimer is on the section', () {
      expect(FilingSection.disclaimer.contains('not a completed tax return'),
          isTrue);
    });
  });

  group('unmatched balance payments sheet', () {
    final r = novReport();

    test('lists only receipts that are still waiting', () {
      expect(r.unmatched.count, 1);
      final u = r.unmatched.rows.single;
      expect(u.code, 'ZKr01');
      expect(u.paidMinor, m(2000));
      expect(u.inPeriod, isTrue);
      expect(u.reason, ReviewReason.noReference.label);
      expect(u.textSnippet, 'Balance');
    });

    test('matches the Summary count', () {
      expect(r.unmatched.count, r.summary.unmatchedCount);
    });

    test('the sheet is not needed when nothing is waiting', () {
      expect(novReport(const ReportInput()).unmatched.isNotEmpty, isFalse);
    });

    test('a receipt from another month is listed but marked outside the period', () {
      final dec = ReportEngine.generate(dataset(),
          ReportPeriod.custom(DateTime(2026, 12, 1), DateTime(2026, 12, 31)));
      expect(dec.unmatched.count, 1);
      expect(dec.unmatched.rows.single.inPeriod, isFalse);
    });

    test('a typo comes with suggestions', () {
      final input = ReportInput(
        legacy: LegacyBalanceResolver.resolve(
          receipts: [
            TestReceipt('ZKc01', nov(3), m(10000), m(4000), customer: 'B').toLegacy(),
            TestReceipt('ZKl01', nov(12), m(6000), m(6000),
                    items: ['Balance ZKc02'], customer: 'B')
                .toLegacy(),
          ],
          manualLinks: const [],
        ),
      );
      final u = novReport(input).unmatched.rows.single;
      expect(u.referencesFound, 'ZKc02');
      expect(u.suggestions.join(','), 'ZKc01');
    });
  });

  group('notes and assumptions', () {
    final r = novReport();

    String joined(NotesSection n) => n.notes.join('\n');

    test('the basis lists the fixed accounting rules', () {
      expect(r.notes.basis.length, 9);
      expect(r.notes.basis.first.startsWith('Sales revenue is counted once'), isTrue);
      expect(r.notes.basis.any((x) => x.contains('Loan receipts are not income')), isTrue);
    });

    test('says the stock adjustment was applied, with the figures', () {
      final text = joined(r.notes);
      expect(text.contains('opening stock 3,000.00 + purchases 6,500.00 - closing stock 4,500.00'),
          isTrue);
    });

    test('says when there is no stock adjustment', () {
      final text = joined(novReport(dataset(withOpeningStock: false)).notes);
      expect(text.contains('No stock adjustment'), isTrue);
    });

    test('mentions waiting balance receipts, write-offs and voided expenses', () {
      final text = joined(r.notes);
      expect(text.contains('1 old balance receipt(s) are not linked'), isTrue);
      expect(text.contains('Settlement adjustments of 1,000.00'), isTrue);
      expect(text.contains('1 voided expense(s)'), isTrue);
    });

    test('mentions the tax estimate and VAT only when set', () {
      expect(joined(r.notes).contains('Estimated tax is an estimate'), isTrue);
      expect(joined(r.notes).contains('VAT collected is worked out'), isFalse);
      expect(joined(novReport(dataset(vat: true)).notes).contains('7.5%'), isTrue);
      expect(joined(novReport(dataset(taxRate: 0)).notes).contains('Estimated tax'), isFalse);
    });

    test('warns when a period does not follow month boundaries', () {
      final partial = ReportEngine.generate(
          dataset(), ReportPeriod.custom(DateTime(2026, 11, 5), DateTime(2026, 11, 20)));
      expect(joined(partial.notes).contains('does not start and end on month boundaries'),
          isTrue);
      expect(joined(r.notes).contains('month boundaries'), isFalse);
    });

    test('warns when the opening cash date is after the period starts', () {
      final input = ReportInput(
        settings: ReportSettings(
            openingCashMinor: m(500), openingCashDate: DateTime(2026, 11, 15)),
      );
      expect(joined(novReport(input).notes).contains('opening cash date is after'), isTrue);
    });

    test('carries the time and version the caller gives', () {
      final stamp = DateTime(2026, 11, 25, 9, 30);
      final rep = ReportEngine.generate(dataset(), novPeriod(),
          generatedAt: stamp, appVersion: '1.2.3');
      expect(rep.notes.generatedAt, stamp);
      expect(rep.notes.appVersion, '1.2.3');
    });

    test('the period line', () {
      expect(r.notes.notes.first, 'Period: 2026-11-01 to 2026-11-30.');
    });
  });
}

/// A straight-line asset in one line, for the tests above.
class AssetSpecForTest {
  static dep.AssetSpec bought(DateTime date, num cost, int months) =>
      dep.AssetSpec(
          purchaseDate: date, costMinor: m(cost), usefulLifeMonths: months);
}
