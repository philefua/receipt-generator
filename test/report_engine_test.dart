import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_generator/features/finance/report_data.dart';
import 'package:receipt_generator/features/finance/report_engine.dart';
import 'package:receipt_generator/features/finance/report_inputs.dart';
import 'package:receipt_generator/features/finance/report_period.dart';

import 'report_fixtures.dart';

String codes(Iterable<SalesRow> rows) => rows.map((r) => r.code).join(',');

void main() {
  group('periods', () {
    final today = DateTime(2026, 11, 24);

    test('this month and last month', () {
      final a = ReportPeriod.thisMonth(today);
      expect(a.from, DateTime(2026, 11, 1));
      expect(a.to, DateTime(2026, 11, 30));
      final b = ReportPeriod.lastMonth(today);
      expect(b.from, DateTime(2026, 10, 1));
      expect(b.to, DateTime(2026, 10, 31));
    });

    test('this month in December ends on the 31st', () {
      expect(ReportPeriod.thisMonth(DateTime(2026, 12, 5)).to, DateTime(2026, 12, 31));
    });

    test('last month in January is December of the year before', () {
      final p = ReportPeriod.lastMonth(DateTime(2027, 1, 9));
      expect(p.from, DateTime(2026, 12, 1));
      expect(p.to, DateTime(2026, 12, 31));
    });

    test('a leap February has 29 days', () {
      final p = ReportPeriod.custom(DateTime(2028, 2, 1), DateTime(2028, 2, 29));
      expect(p.days, 29);
    });

    test('a range given backwards is put right', () {
      final p = ReportPeriod.custom(DateTime(2026, 11, 30), DateTime(2026, 11, 1));
      expect(p.from, DateTime(2026, 11, 1));
      expect(p.days, 30);
    });

    test('contains includes both ends', () {
      final p = ReportPeriod.custom(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
      expect(p.contains(DateTime(2026, 11, 1, 0, 1)), isTrue);
      expect(p.contains(DateTime(2026, 11, 30, 23, 59)), isTrue);
      expect(p.contains(DateTime(2026, 12, 1)), isFalse);
      expect(p.contains(DateTime(2026, 10, 31, 23, 59)), isFalse);
    });

    test('January financial year', () {
      final fy = ReportPeriod.thisFinancialYear(today, 1);
      expect(fy.from, DateTime(2026, 1, 1));
      expect(fy.to, DateTime(2026, 12, 31));
      final last = ReportPeriod.lastFinancialYear(today, 1);
      expect(last.from, DateTime(2025, 1, 1));
      expect(last.to, DateTime(2025, 12, 31));
      final q = ReportPeriod.thisQuarter(today, 1);
      expect(q.from, DateTime(2026, 10, 1));
      expect(q.to, DateTime(2026, 12, 31));
    });

    test('April financial year', () {
      final fy = ReportPeriod.thisFinancialYear(today, 4);
      expect(fy.from, DateTime(2026, 4, 1));
      expect(fy.to, DateTime(2027, 3, 31));
      final last = ReportPeriod.lastFinancialYear(today, 4);
      expect(last.from, DateTime(2025, 4, 1));
      expect(last.to, DateTime(2026, 3, 31));
      final q = ReportPeriod.thisQuarter(today, 4);
      expect(q.from, DateTime(2026, 10, 1));
      expect(q.to, DateTime(2026, 12, 31));
    });

    test('April financial year in January belongs to the year before', () {
      final jan = DateTime(2027, 1, 15);
      final fy = ReportPeriod.thisFinancialYear(jan, 4);
      expect(fy.from, DateTime(2026, 4, 1));
      expect(fy.to, DateTime(2027, 3, 31));
      final q = ReportPeriod.thisQuarter(jan, 4);
      expect(q.from, DateTime(2027, 1, 1));
      expect(q.to, DateTime(2027, 3, 31));
    });

    test('quarters follow the financial year start month', () {
      final q = ReportPeriod.thisQuarter(today, 2); // Feb start: Nov-Jan
      expect(q.from, DateTime(2026, 11, 1));
      expect(q.to, DateTime(2027, 1, 31));
    });

    test('a start month outside 1-12 is held to the nearest', () {
      expect(ReportPeriod.thisFinancialYear(today, 0).from, DateTime(2026, 1, 1));
    });
  });

  group('sales', () {
    final r = novReport();

    test('which receipts are sales', () {
      // Not in: last month, December, the app balance receipt, and the old
      // balance receipt that was linked by itself (ZKl01).
      expect(codes(r.sales.rows), 'ZKb01,ZKc01,ZKe01,ZKf01,ZKj01,ZKo01,ZKr01');
      expect(r.sales.count, 7);
    });

    test('totals', () {
      expect(r.sales.revenueMinor, m(149000));
      expect(r.sales.discountMinor, m(500));
      expect(r.sales.depositMinor, m(138000));
    });

    test('a receipt that also paid an old balance counts only its new items', () {
      final row = r.sales.rows.firstWhere((x) => x.code == 'ZKo01');
      expect(row.totalMinor, m(7000));
      expect(row.revenueMinor, m(3000));
      expect(row.status, 'Includes old balance payment');
    });

    test('an old receipt not yet linked stays in sales and is flagged', () {
      final row = r.sales.rows.firstWhere((x) => x.code == 'ZKr01');
      expect(row.revenueMinor, m(2000));
      expect(row.status, 'Possible balance payment (unmatched)');
    });

    test('status follows what is still owed at the end', () {
      String s(String c) => r.sales.rows.firstWhere((x) => x.code == c).status;
      expect(s('ZKb01'), 'Paid');
      expect(s('ZKc01'), 'Owing');
    });

    test('by day and by month', () {
      expect(r.sales.byDay.length, 7);
      expect(r.sales.byDay.first.key, DateTime(2026, 11, 2));
      expect(r.sales.byMonth.length, 1);
      expect(r.sales.byMonth.first.count, 7);
      expect(r.sales.byMonth.first.revenueMinor, m(149000));
      final d15 = r.sales.byDay.firstWhere((b) => b.key == DateTime(2026, 11, 15));
      expect(d15.revenueMinor, m(3000));
    });

    test('a period crossing a year end splits by month', () {
      final input = dataset(extraReceipts: [
        TestReceipt('YAj01', DateTime(2027, 1, 10, 10), m(5000), m(5000)),
      ]);
      final rep = ReportEngine.generate(
          input, ReportPeriod.custom(DateTime(2026, 12, 1), DateTime(2027, 1, 31)));
      expect(rep.sales.byMonth.length, 2);
      expect(rep.sales.byMonth.first.key, DateTime(2026, 12));
      expect(rep.sales.byMonth.last.key, DateTime(2027, 1));
      expect(rep.sales.revenueMinor, m(9999) + m(5000));
    });
  });

  group('expenses', () {
    final r = novReport();

    test('totals leave out voided and not-in-P&L', () {
      expect(r.expenses.directMinor, m(6500));
      expect(r.expenses.operatingMinor, m(17500));
      expect(r.expenses.totalMinor, m(24000));
      expect(r.expenses.notInPnlMinor, m(5000));
    });

    test('rows', () {
      expect(r.expenses.rows.length, 5);
      expect(r.expenses.notInPnlRows.length, 2);
      expect(r.expenses.voidedRows.length, 1);
      expect(r.expenses.voidedRows.first.voided, isTrue);
    });

    test('last month is not in this month', () {
      expect(r.expenses.rows.any((x) => x.amountMinor == m(7000)), isFalse);
    });

    test('by category, direct before operating, biggest first', () {
      final names = r.expenses.byCategory.map((c) => c.name).join(',');
      expect(names, 'Toner,Paper,Rent,Wages,Fuel / generator');
    });

    test('by month', () {
      expect(r.expenses.byMonth.length, 1);
      expect(r.expenses.byMonth.first.directMinor, m(6500));
      expect(r.expenses.byMonth.first.operatingMinor, m(17500));
    });
  });

  group('profit and loss', () {
    final r = novReport();
    final p = r.pnl;

    test('revenue and settlement adjustment', () {
      expect(p.revenueMinor, m(149000));
      expect(p.settlementAdjustmentsMinor, m(1000));
    });

    test('stock adjustment: opening + purchases - closing', () {
      expect(p.stockAdjusted, isTrue);
      expect(p.openingStockMinor, m(3000));
      expect(p.closingStockMinor, m(4500));
      expect(p.purchasesMinor, m(6500));
      expect(p.directCostsMinor, m(5000));
    });

    test('gross profit and operating profit', () {
      expect(p.grossProfitMinor, m(143000));
      expect(p.operatingExpensesMinor, m(17500));
      expect(p.operatingProfitBeforeDepreciationMinor, m(125500));
    });

    test('depreciation comes from the register, voided and fully depreciated assets add nothing', () {
      // A1 10,000 + A2 1,408.82 (reducing balance) + A4 1,000 + A5 1,000 + A6 1,000
      expect(p.depreciationMinor, 1440882);
    });

    test('gain or loss on assets retired this month', () {
      // A4: sold for 40,000, book value 49,000 = loss 9,000.
      // A5: scrapped, book value 13,000 = loss 13,000.
      expect(p.disposalGainLossMinor, -m(22000));
    });

    test('operating profit, interest and net profit', () {
      expect(p.operatingProfitMinor, 8909118);
      expect(p.interestPaidMinor, m(7000));
      expect(p.netProfitBeforeTaxMinor, 8209118);
    });

    test('estimated tax is rate x profit', () {
      expect(p.estimatedTaxMinor, 2462735);
      expect(p.netProfitAfterTaxMinor, 8209118 - 2462735);
    });

    test('tax is zero when the rate is off', () {
      expect(novReport(dataset(taxRate: 0)).pnl.estimatedTaxMinor, 0);
    });

    test('tax is zero on a loss', () {
      final loss = ReportInput(
        settings: const ReportSettings(estimatedTaxRatePercent: 30),
        expenses: [
          exp('x', nov(3), 'seed_op_rent', 'Rent', 'operating', 1000, 'Cash'),
        ],
      );
      final rep = novReport(loss);
      expect(rep.pnl.netProfitBeforeTaxMinor, -m(1000));
      expect(rep.pnl.estimatedTaxMinor, 0);
      expect(rep.pnl.netProfitAfterTaxMinor, -m(1000));
    });

    test('with no opening count the stock adjustment is not applied', () {
      final rep = novReport(dataset(withOpeningStock: false));
      expect(rep.pnl.stockAdjusted, isFalse);
      expect(rep.pnl.openingStockMinor, isNull);
      expect(rep.pnl.directCostsMinor, m(6500));
    });

    test('Not in P&L money never reaches the P&L', () {
      // Drawings 3,000 and tax 2,000 are not in operating expenses.
      expect(p.operatingExpensesMinor, m(17500));
    });
  });

  group('cashflow', () {
    final r = novReport();
    final c = r.cashflow;

    test('opening cash is the starting balance moved on to the period start', () {
      // 10,000 at 1 Oct, + 4,000 received 30 Oct, - 7,000 paid 31 Oct.
      expect(c.openingBalanceMinor, m(7000));
      expect(c.openingCashAfterPeriodStart, isFalse);
    });

    test('money in from operations', () {
      // Deposits: 10,000 + 5,000 + 8,000 + 100,000 + 6,000 + 3,000 (new items
      // on ZKo01) + 2,000 (unmatched) = 134,000.
      expect(c.salesDepositsMinor, m(134000));
      // Balance payments: ZKl01 5,000 + 4,000 of ZKo01 + app receipt 3,000.
      expect(c.balancePaymentsMinor, m(12000));
      expect(c.operatingInMinor, m(146000));
    });

    test('money out from operations', () {
      expect(c.expensesPaidMinor, m(24000));
      expect(c.taxesRemittedMinor, m(2000));
      expect(c.operatingOutMinor, m(26000));
      expect(c.netOperatingMinor, m(120000));
    });

    test('investing: purchases and sale proceeds, no cash for equipment already owned', () {
      expect(c.assetPurchasesMinor, m(120000));
      expect(c.disposalProceedsMinor, m(40000));
      expect(c.netInvestingMinor, -m(80000));
    });

    test('financing: loan received, repayments, interest, drawings', () {
      expect(c.loansReceivedMinor, m(200000));
      expect(c.principalRepaidMinor, m(35000));
      expect(c.interestPaidMinor, m(7000));
      expect(c.ownerDrawingsMinor, m(3000));
      expect(c.netFinancingMinor, m(155000));
    });

    test('net change and closing balance', () {
      expect(c.netChangeMinor, m(195000));
      expect(c.closingBalanceMinor, m(202000));
      expect(c.cashInMinor, m(386000));
      expect(c.cashOutMinor, m(191000));
    });

    test('breakdown by method adds up to the same totals', () {
      String line(MethodCash x) => '${x.method}:${x.inMinor}:${x.outMinor}';
      expect(
          c.byMethod.map(line).join('|'),
          'Bank transfer:${m(200000)}:${m(164500)}|'
          'Cash:${m(32000)}:${m(26500)}|'
          'Not recorded:${m(40000)}:0|'
          'POS:${m(6000)}:0|'
          'Transfer:${m(108000)}:0');
      expect(c.byMethod.fold<int>(0, (s, x) => s + x.inMinor), c.cashInMinor);
      expect(c.byMethod.fold<int>(0, (s, x) => s + x.outMinor), c.cashOutMinor);
    });

    test('a write-off moves no cash', () {
      final without = novReport(dataset(withWriteoff: false));
      expect(without.cashflow.closingBalanceMinor, c.closingBalanceMinor);
      expect(without.cashflow.netChangeMinor, c.netChangeMinor);
    });

    test('an opening cash date after the period start is flagged', () {
      final input = ReportInput(
        settings: ReportSettings(
          openingCashMinor: m(500),
          openingCashDate: DateTime(2026, 11, 15),
        ),
      );
      final rep = novReport(input);
      expect(rep.cashflow.openingCashAfterPeriodStart, isTrue);
      expect(rep.cashflow.openingBalanceMinor, m(500));
    });

    test('with no opening cash date all earlier movements are counted', () {
      final input = ReportInput(
        settings: ReportSettings(openingCashMinor: m(1000)),
        receipts: [TestReceipt('ZJd30', DateTime(2026, 10, 30), m(300), m(300)).toReport()],
      );
      expect(novReport(input).cashflow.openingBalanceMinor, m(1300));
    });
  });

  group('receivables', () {
    final r = novReport();

    test('what is still owed on the last day', () {
      expect(r.receivables.rows.map((x) => x.code).join(','), 'ZJd30,ZKc01');
      expect(r.receivables.rows[0].outstandingMinor, m(8000));
      expect(r.receivables.rows[1].outstandingMinor, m(2000));
      expect(r.receivables.totalMinor, m(10000));
    });

    test('age in days from the receipt date to the end of the period', () {
      expect(r.receivables.rows[0].ageDays, 31);
      expect(r.receivables.rows[1].ageDays, 27);
    });

    test('deposit, balance payments, old receipts and write-offs all reduce it', () {
      final row = r.receivables.rows[1];
      expect(row.totalMinor, m(20000));
      // 5,000 deposit + 3,000 app + 5,000 + 4,000 old receipts + 1,000 write-off
      expect(row.settledMinor, m(18000));
    });

    test('a write-off lowers revenue and what is owed, not cash', () {
      final without = novReport(dataset(withWriteoff: false));
      expect(without.receivables.totalMinor, m(11000));
      expect(without.pnl.settlementAdjustmentsMinor, 0);
      expect(without.pnl.grossProfitMinor, r.pnl.grossProfitMinor + m(1000));
    });

    test('a payment made after the period is not counted in it', () {
      final input = ReportInput(
        receipts: [
          TestReceipt('ZKc01', nov(3), m(5000), 0).toReport(),
          TestReceipt('ZLe05-B', DateTime(2026, 12, 5), m(5000), m(5000),
                  balanceType: true, linked: 'ZKc01')
              .toReport(),
        ],
      );
      expect(novReport(input).receivables.totalMinor, m(5000));
      final dec = ReportEngine.generate(
          input, ReportPeriod.custom(DateTime(2026, 12, 1), DateTime(2026, 12, 31)));
      expect(dec.receivables.totalMinor, 0);
    });

    test('a sale made after the period is not listed', () {
      final input = ReportInput(
        receipts: [TestReceipt('ZLb01', DateTime(2026, 12, 2), m(900), 0).toReport()],
      );
      expect(novReport(input).receivables.rows, isEmpty);
    });

    test('over-paid data never shows a negative balance', () {
      final input = ReportInput(
        receipts: [
          TestReceipt('ZKc01', nov(3), m(1000), 0).toReport(),
          TestReceipt('ZKd05-B', nov(5), m(1500), m(1500), balanceType: true, linked: 'ZKc01')
              .toReport(),
        ],
      );
      expect(novReport(input).receivables.rows, isEmpty);
    });
  });

  group('assets and loans in the summary', () {
    final s = novReport().summary;

    test('net book value counts assets still held on the last day', () {
      // A1 110,000 + A2 830.. 83,120.56 + A3 0 + A6 37,000. A4 and A5 are
      // retired and A7 is voided.
      expect(s.assetNetBookValueMinor, 23012056);
    });

    test('loans outstanding skip the voided loan and the voided repayment', () {
      // LN1 200,000 - 25,000 + LN2 50,000 - 10,000.
      expect(s.loansOutstandingMinor, m(215000));
    });
  });

  group('summary agrees with the sheets', () {
    final r = novReport();
    final s = r.summary;

    test('same figures everywhere', () {
      expect(s.totalSalesMinor, r.sales.revenueMinor);
      expect(s.totalSalesMinor, r.pnl.revenueMinor);
      expect(s.totalExpensesMinor, r.expenses.totalMinor);
      expect(s.grossProfitMinor, r.pnl.grossProfitMinor);
      expect(s.netProfitMinor, r.pnl.netProfitBeforeTaxMinor);
      expect(s.estimatedTaxMinor, r.pnl.estimatedTaxMinor);
      expect(s.netProfitAfterTaxMinor, r.pnl.netProfitAfterTaxMinor);
      expect(s.depreciationMinor, r.pnl.depreciationMinor);
      expect(s.interestPaidMinor, r.cashflow.interestPaidMinor);
      expect(s.cashNetMinor, s.cashInMinor - s.cashOutMinor);
      expect(s.receivablesMinor, r.receivables.totalMinor);
      expect(s.balancePaymentsCollectedMinor, r.cashflow.balancePaymentsMinor);
    });

    test('closing cash is opening plus net change', () {
      expect(r.cashflow.closingBalanceMinor,
          r.cashflow.openingBalanceMinor + r.cashflow.netChangeMinor);
    });

    test('top categories', () {
      expect(s.topCategories.map((c) => c.name).join(','),
          'Rent,Wages,Toner,Paper,Fuel / generator');
    });

    test('old receipts waiting to be linked are counted', () {
      expect(s.unmatchedCount, 1);
    });

    test('profit chain adds up', () {
      final p = r.pnl;
      expect(
          p.netProfitBeforeTaxMinor,
          p.revenueMinor -
              p.settlementAdjustmentsMinor -
              p.directCostsMinor -
              p.operatingExpensesMinor -
              p.depreciationMinor +
              p.disposalGainLossMinor -
              p.interestPaidMinor);
    });
  });

  group('empty and quiet periods', () {
    test('no records gives zeros and an untouched opening balance', () {
      final rep = novReport(ReportInput(
        settings: ReportSettings(
            openingCashMinor: m(2500), openingCashDate: DateTime(2026, 1, 1)),
      ));
      expect(rep.sales.count, 0);
      expect(rep.sales.revenueMinor, 0);
      expect(rep.expenses.totalMinor, 0);
      expect(rep.pnl.netProfitBeforeTaxMinor, 0);
      expect(rep.cashflow.netChangeMinor, 0);
      expect(rep.cashflow.closingBalanceMinor, m(2500));
      expect(rep.receivables.rows, isEmpty);
      expect(rep.summary.topCategories, isEmpty);
    });

    test('a month with nothing in it still reports assets and loans carried forward', () {
      final rep = ReportEngine.generate(dataset(),
          ReportPeriod.custom(DateTime(2027, 3, 1), DateTime(2027, 3, 31)));
      expect(rep.sales.count, 0);
      expect(rep.summary.loansOutstandingMinor, m(215000));
    });
  });
}
