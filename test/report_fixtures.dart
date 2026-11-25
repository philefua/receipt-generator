// Shared hand-checked dataset for the report engine tests.
import 'package:receipt_generator/features/finance/depreciation.dart';
import 'package:receipt_generator/features/finance/legacy_balance_resolver.dart';
import 'package:receipt_generator/features/finance/loan_math.dart';
import 'package:receipt_generator/features/finance/report_data.dart';
import 'package:receipt_generator/features/finance/report_engine.dart';
import 'package:receipt_generator/features/finance/report_inputs.dart';
import 'package:receipt_generator/features/finance/report_period.dart';

// All expected figures below were worked out by hand from the dataset in
// `dataset()`, and the reducing-balance depreciation was checked with a
// separate calculation. Money is whole minor units: m(10000) = 10,000.00.
int m(num naira) => (naira * 100).round();

DateTime nov(int day) => DateTime(2026, 11, day, 10);

class TestReceipt {
  final String code;
  final DateTime at;
  final int total;
  final int deposit;
  final List<String> items;
  final String customer;
  final String method;
  final int discount;
  final bool balanceType;
  final String? linked;
  const TestReceipt(
    this.code,
    this.at,
    this.total,
    this.deposit, {
    this.items = const ['Banner'],
    this.customer = '',
    this.method = 'Cash',
    this.discount = 0,
    this.balanceType = false,
    this.linked,
  });

  ReportReceipt toReport() => ReportReceipt(
        code: code,
        issuedAt: at,
        isBalancePayment: balanceType,
        linkedCode: linked,
        customerName: customer,
        itemsSummary: items.join(', '),
        totalMinor: total,
        discountMinor: discount,
        depositMinor: deposit,
        balanceAtTimeMinor: total - deposit,
        paymentMethod: method,
      );

  LegacyReceiptRecord toLegacy() => LegacyReceiptRecord(
        code: code,
        issuedAt: at,
        isBalanceType: balanceType,
        linkedCode: linked,
        customerName: customer,
        itemNames: items,
        totalMinor: total,
        depositMinor: deposit,
      );
}

ReportExpense exp(String id, DateTime date, String catId, String catName,
        String group, num amount, String paidFrom,
        {bool voided = false, num? inputVat}) =>
    ReportExpense(
      id: id,
      date: date,
      categoryId: catId,
      categoryName: catName,
      group: group,
      amountMinor: m(amount),
      paidFrom: paidFrom,
      inputVatMinor: inputVat == null ? null : m(inputVat),
      voided: voided,
    );

ReportAsset asset(String id, AssetSpec spec,
        {bool opening = false, String method = 'Bank transfer'}) =>
    ReportAsset(
        id: id, name: id, spec: spec, isOpeningBalance: opening, paymentMethod: method);

ReportRepayment repay(String loanId, DateTime date, num principal, num interest,
        String method,
        {bool voided = false}) =>
    ReportRepayment(
      spec: RepaymentSpec(
        loanId: loanId,
        date: date,
        principalMinor: m(principal),
        interestMinor: m(interest),
        voided: voided,
      ),
      paymentMethod: method,
    );

/// The shop in November 2026. See the comments for what each record tests.
ReportInput dataset({
  bool withWriteoff = true,
  bool withOpeningStock = true,
  double taxRate = 30,
  bool vat = false,
  List<TestReceipt> extraReceipts = const [],
}) {
  final rs = <TestReceipt>[
    // Last month: owes 8,000 and is still owing at the end of November.
    TestReceipt('ZJd30', DateTime(2026, 10, 30, 9), m(12000), m(4000), customer: 'C'),
    TestReceipt('ZKb01', nov(2), m(10000), m(10000), discount: m(500), customer: 'A'),
    // Owes 15,000 at first. Paid down by three kinds of payment, then settled.
    TestReceipt('ZKc01', nov(3), m(20000), m(5000), customer: 'B'),
    TestReceipt('ZKe01', nov(5), m(8000), m(8000), method: 'Transfer'),
    TestReceipt('ZKf01', nov(6), m(100000), m(100000), method: 'Transfer'),
    TestReceipt('ZKj01', nov(10), m(6000), m(6000), method: 'POS'),
    // Old typed balance receipt, only the original number: links by itself.
    TestReceipt('ZKl01', nov(12), m(5000), m(5000), items: ['ZKc01'], customer: 'B'),
    // Old typed receipt that also sold new items: linked by hand, 4,000 applied.
    TestReceipt('ZKo01', nov(15), m(7000), m(7000),
        items: ['Balance ZKc01', 'Banner'], customer: 'B'),
    // Says "balance" but names no sale: stays unmatched, counted as a sale.
    TestReceipt('ZKr01', nov(18), m(2000), m(2000), items: ['Balance'], customer: 'D'),
    // Balance payment made with the app.
    TestReceipt('ZKt01-B', nov(20), m(3000), m(3000),
        balanceType: true, linked: 'ZKc01', customer: 'B'),
    // After the period.
    TestReceipt('ZLb01', DateTime(2026, 12, 2, 10), m(9999), m(9999)),
    ...extraReceipts,
  ];

  final writeoffs = withWriteoff
      ? [
          ReportWriteoff(
              receiptCode: 'ZKc01',
              date: nov(25),
              amountMinor: m(1000),
              reason: 'Customer short'),
        ]
      : <ReportWriteoff>[];

  final legacy = LegacyBalanceResolver.resolve(
    receipts: [for (final r in rs) r.toLegacy()],
    manualLinks: [
      ManualLinkRecord(
          id: 'm1',
          receiptCode: 'ZKo01',
          originalCode: 'ZKc01',
          appliedMinor: m(4000)),
    ],
    writeoffs: {
      for (final w in writeoffs) w.receiptCode: w.amountMinor,
    },
  );

  return ReportInput(
    settings: ReportSettings(
      financialYearStartMonth: 1,
      estimatedTaxRatePercent: taxRate,
      vatEnabled: vat,
      vatRatePercent: vat ? 7.5 : 0,
      openingCashMinor: m(10000),
      openingCashDate: DateTime(2026, 10, 1),
    ),
    receipts: [for (final r in rs) r.toReport()],
    writeoffs: writeoffs,
    legacy: legacy,
    stockCounts: [
      if (withOpeningStock)
        ReportStockCount(date: DateTime(2026, 10, 31), valueMinor: m(3000)),
      ReportStockCount(date: DateTime(2026, 11, 30), valueMinor: m(4500)),
    ],
    expenses: [
      exp('e1', nov(3), 'seed_direct_toner', 'Toner', 'direct', 4000, 'Cash',
          inputVat: 300),
      exp('e2', nov(8), 'seed_direct_paper', 'Paper', 'direct', 2500, 'Bank transfer'),
      exp('e3', nov(9), 'seed_op_rent', 'Rent', 'operating', 10000, 'Bank transfer',
          inputVat: 750),
      exp('e4', nov(14), 'seed_op_wages', 'Wages', 'operating', 6000, 'Cash'),
      exp('e5', nov(20), 'seed_op_fuel', 'Fuel / generator', 'operating', 1500, 'Cash'),
      exp('e6', nov(22), 'seed_np_drawings', 'Owner drawings', 'non_pnl', 3000, 'Cash'),
      exp('e7', nov(23), 'seed_np_tax', 'Tax remittances', 'non_pnl', 2000, 'Bank transfer'),
      exp('e8', nov(24), 'seed_op_marketing', 'Marketing', 'operating', 9999, 'Cash',
          voided: true, inputVat: 999),
      // Last month: moves the opening cash, not this month's figures.
      exp('e9', DateTime(2026, 10, 31), 'seed_direct_toner', 'Toner', 'direct', 7000,
          'Cash'),
    ],
    assets: [
      // Bought this month: 10,000 a month, 120,000 leaves the bank.
      asset(
          'A1',
          AssetSpec(
              purchaseDate: nov(5),
              costMinor: m(120000),
              usefulLifeMonths: 12)),
      // Reducing balance 20%, bought in January.
      asset(
          'A2',
          AssetSpec(
              purchaseDate: DateTime(2026, 1, 15),
              costMinor: m(100000),
              usefulLifeMonths: 60,
              reducingBalance: true,
              annualRatePercent: 20)),
      // Owned before the app and already fully depreciated.
      asset(
          'A3',
          AssetSpec(
              purchaseDate: DateTime(2023, 1, 10),
              costMinor: m(36000),
              usefulLifeMonths: 36),
          opening: true),
      // Retired this month for 40,000. Charged for November, then stops.
      asset(
          'A4',
          AssetSpec(
              purchaseDate: DateTime(2026, 1, 15),
              costMinor: m(60000),
              usefulLifeMonths: 60,
              retiredDate: nov(18),
              proceedsMinor: m(40000))),
      // Scrapped this month for nothing.
      asset(
          'A5',
          AssetSpec(
              purchaseDate: DateTime(2026, 1, 15),
              costMinor: m(24000),
              usefulLifeMonths: 24,
              retiredDate: nov(10))),
      // Owned before the app, still depreciating, no cash.
      asset(
          'A6',
          AssetSpec(
              purchaseDate: DateTime(2025, 1, 10),
              costMinor: m(60000),
              usefulLifeMonths: 60),
          opening: true),
      // Voided: left out of everything.
      asset(
          'A7',
          AssetSpec(
              purchaseDate: nov(6),
              costMinor: m(50000),
              usefulLifeMonths: 12,
              voided: true)),
    ],
    loans: [
      ReportLoan(
          id: 'LN1',
          lenderName: 'Bank',
          spec: LoanSpec(
              id: 'LN1', dateReceived: nov(4), principalMinor: m(200000)),
          receivedInto: 'Bank transfer'),
      // Existed before the app: no cash inflow.
      ReportLoan(
          id: 'LN2',
          lenderName: 'Cooperative',
          spec: LoanSpec(
              id: 'LN2',
              dateReceived: DateTime(2026, 10, 1),
              principalMinor: m(50000)),
          isOpeningBalance: true),
      ReportLoan(
          id: 'LN3',
          lenderName: 'Voided',
          spec: LoanSpec(
              id: 'LN3',
              dateReceived: nov(7),
              principalMinor: m(99999),
              voided: true),
          receivedInto: 'Cash'),
    ],
    repayments: [
      repay('LN2', nov(12), 10000, 2000, 'Cash'),
      repay('LN1', nov(20), 20000, 4000, 'Bank transfer'),
      repay('LN1', nov(28), 5000, 1000, 'Bank transfer'),
      repay('LN1', nov(29), 100000, 9999, 'Bank transfer', voided: true),
    ],
  );
}

ReportData novReport([ReportInput? input]) => ReportEngine.generate(
    input ?? dataset(), ReportPeriod.custom(DateTime(2026, 11, 1), DateTime(2026, 11, 30)));

