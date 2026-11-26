import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_generator/features/finance/models/expense.dart';
import 'package:receipt_generator/features/finance/models/expense_category.dart';
import 'package:receipt_generator/features/finance/models/finance_settings.dart';
import 'package:receipt_generator/features/finance/models/receipt_link.dart';
import 'package:receipt_generator/features/finance/report_adapter.dart';
import 'package:receipt_generator/features/finance/report_engine.dart';
import 'package:receipt_generator/features/finance/report_period.dart';
import 'package:receipt_generator/models/receipt.dart';

FinanceSettings _settings() =>
    FinanceSettings(paidFromOptions: List<String>.of(FinanceSettings.defaultPaidFrom));

Receipt _sale(
  String code,
  DateTime when, {
  required double total,
  required double deposit,
  required double balance,
  List<String> items = const ['Flyers'],
  String customer = 'Ada',
}) =>
    Receipt(
      receiptCode: code,
      issuedAt: when,
      items: [
        for (final n in items)
          ReceiptItem(
              productId: 'p', name: n, unitPrice: total, quantity: 1, lineTotal: total),
      ],
      subtotal: total,
      discountPercent: 0,
      discountAmount: 0,
      totalPayable: total,
      cashierName: 'Front Desk',
      customerName: customer,
      customerWhatsapp: '08030000000',
      depositPaid: deposit,
      balanceOwed: balance,
    );

Receipt _balanceReceipt(String code, DateTime when, String original, double amount) =>
    Receipt(
      receiptCode: code,
      issuedAt: when,
      items: const [],
      subtotal: amount,
      discountPercent: 0,
      discountAmount: 0,
      totalPayable: amount,
      cashierName: 'Front Desk',
      customerName: 'Ada',
      depositPaid: amount,
      balanceOwed: 0,
      receiptType: Receipt.typeBalancePayment,
      linkedReceiptId: original,
    );

final _period = ReportPeriod.custom(DateTime(2026, 11, 1), DateTime(2026, 11, 30));

void main() {
  test('zero deposit and zero balance is read as fully paid', () {
    final input = ReportAdapter.build(
      financeSettings: _settings(),
      receipts: [
        _sale('ZKb01', DateTime(2026, 11, 2), total: 5000, deposit: 0, balance: 0),
      ],
    );
    expect(input.receipts.single.depositMinor, 500000);

    final data = ReportEngine.generate(input, _period);
    expect(data.sales.revenueMinor, 500000);
    expect(data.receivables.totalMinor, 0);
  });

  test('zero deposit with a balance owed stays unpaid', () {
    final input = ReportAdapter.build(
      financeSettings: _settings(),
      receipts: [
        _sale('ZKb01', DateTime(2026, 11, 2), total: 5000, deposit: 0, balance: 5000),
      ],
    );
    expect(input.receipts.single.depositMinor, 0);
    expect(input.receipts.single.balanceAtTimeMinor, 500000);

    final data = ReportEngine.generate(input, _period);
    expect(data.receivables.totalMinor, 500000);
  });

  test('a -B balance receipt is cash, not a sale, and lowers receivables', () {
    final input = ReportAdapter.build(
      financeSettings: _settings(),
      receipts: [
        _sale('ZKb01', DateTime(2026, 11, 2), total: 5000, deposit: 2000, balance: 3000),
        _balanceReceipt('ZKe05-B', DateTime(2026, 11, 5), 'ZKb01', 1000),
      ],
    );
    final data = ReportEngine.generate(input, _period);
    expect(data.sales.count, 1);
    expect(data.sales.revenueMinor, 500000);
    expect(data.cashflow.balancePaymentsMinor, 100000);
    expect(data.receivables.totalMinor, 200000);
  });

  test('an old typed balance receipt is matched and not counted as a sale', () {
    final input = ReportAdapter.build(
      financeSettings: _settings(),
      receipts: [
        _sale('ZKq01', DateTime(2026, 11, 2), total: 10000, deposit: 4000, balance: 6000),
        _sale('ZKq09', DateTime(2026, 11, 10),
            total: 6000,
            deposit: 6000,
            balance: 0,
            items: ['Balance ZKq01']),
      ],
    );
    expect(input.legacy.linked.length, 1);
    expect(input.legacy.needsReviewCount, 0);

    final data = ReportEngine.generate(input, _period);
    expect(data.sales.count, 1);
    expect(data.sales.revenueMinor, 1000000);
    expect(data.receivables.totalMinor, 0);
  });

  test('an old typed balance receipt with zero deposit and balance is matched', () {
    final input = ReportAdapter.build(
      financeSettings: _settings(),
      receipts: [
        _sale('ZKq01', DateTime(2026, 11, 2), total: 10000, deposit: 4000, balance: 6000),
        _sale('ZKq09', DateTime(2026, 11, 10),
            total: 6000, deposit: 0, balance: 0, items: ['Balance ZKq01']),
      ],
    );
    expect(input.legacy.linked.length, 1);
    expect(input.legacy.linked.single.appliedMinor, 600000);
  });

  test('write-offs come from active records only', () {
    final links = [
      ReceiptLink(
          id: 'w1',
          kind: ReceiptLink.kindWriteoff,
          receiptCode: 'ZKb01',
          originalReceiptCode: 'ZKb01',
          amount: 500,
          reason: 'Small leftover',
          createdAt: DateTime(2026, 11, 8)),
      ReceiptLink(
          id: 'w2',
          kind: ReceiptLink.kindWriteoff,
          receiptCode: 'ZKb01',
          originalReceiptCode: 'ZKb01',
          amount: 300,
          reason: 'Mistake',
          createdAt: DateTime(2026, 11, 9),
          voidedAt: DateTime(2026, 11, 9)),
    ];
    final input = ReportAdapter.build(
      financeSettings: _settings(),
      receipts: [
        _sale('ZKb01', DateTime(2026, 11, 2), total: 5000, deposit: 2000, balance: 3000),
      ],
      links: links,
    );
    expect(input.writeoffs.length, 1);
    expect(input.writeoffs.single.amountMinor, 50000);

    final data = ReportEngine.generate(input, _period);
    expect(data.receivables.totalMinor, 250000);
  });

  test('expenses carry category name, group and void state', () {
    final input = ReportAdapter.build(
      financeSettings: _settings(),
      expenseCategories: [
        ExpenseCategory(
            id: 'c1',
            name: 'Toner',
            group: ExpenseCategory.groupDirect,
            createdAt: DateTime(2026, 1, 1)),
      ],
      expenses: [
        Expense(
          id: 'e1',
          date: DateTime(2026, 11, 3),
          createdAt: DateTime(2026, 11, 3),
          amount: 1200.5,
          categoryId: 'c1',
          categoryType: ExpenseCategory.groupDirect,
          paidFrom: 'Cash',
          inputVat: 80,
          createdByRole: Expense.roleManager,
        ),
        Expense(
          id: 'e2',
          date: DateTime(2026, 11, 4),
          createdAt: DateTime(2026, 11, 4),
          amount: 100,
          categoryId: 'gone',
          categoryType: ExpenseCategory.groupOperating,
          paidFrom: 'Cash',
          createdByRole: Expense.roleCashier,
          voidedAt: DateTime(2026, 11, 5),
          voidReason: 'Duplicate',
        ),
      ],
    );
    final first = input.expenses[0];
    expect(first.categoryName, 'Toner');
    expect(first.group, 'direct');
    expect(first.amountMinor, 120050);
    expect(first.inputVatMinor, 8000);
    expect(first.whtMinor, isNull);

    final second = input.expenses[1];
    expect(second.categoryName, ReportAdapter.unknownCategory);
    expect(second.voided, isTrue);
    expect(second.voidReason, 'Duplicate');
  });

  test('settings are converted to minor units', () {
    final s = _settings()
      ..financialYearStartMonth = 4
      ..vatEnabled = true
      ..vatRatePercent = 7.5
      ..openingCashBalance = 25000.5
      ..openingCashDate = DateTime(2026, 1, 1);
    final input = ReportAdapter.build(financeSettings: s);
    expect(input.settings.financialYearStartMonth, 4);
    expect(input.settings.vatEnabled, isTrue);
    expect(input.settings.vatRatePercent, 7.5);
    expect(input.settings.openingCashMinor, 2500050);
    expect(input.settings.openingCashDate, DateTime(2026, 1, 1));
  });

  test('an empty shop gives an empty input', () {
    final input = ReportAdapter.build(financeSettings: _settings());
    expect(input.receipts, isEmpty);
    final data = ReportEngine.generate(input, _period);
    expect(data.sales.count, 0);
    expect(data.receivables.totalMinor, 0);
  });
}
