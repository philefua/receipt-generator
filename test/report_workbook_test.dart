import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_generator/features/finance/models/expense.dart';
import 'package:receipt_generator/features/finance/models/expense_category.dart';
import 'package:receipt_generator/features/finance/models/finance_settings.dart';
import 'package:receipt_generator/features/finance/report_adapter.dart';
import 'package:receipt_generator/features/finance/report_data.dart';
import 'package:receipt_generator/features/finance/report_engine.dart';
import 'package:receipt_generator/features/finance/report_period.dart';
import 'package:receipt_generator/features/finance/report_workbook.dart';
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
      customerName: 'Ada',
      customerWhatsapp: '08030000000',
      depositPaid: deposit,
      balanceOwed: balance,
    );

final _period = ReportPeriod.custom(DateTime(2026, 11, 1), DateTime(2026, 11, 30));

ReportData _report(List<Receipt> receipts, {List<Expense> expenses = const []}) {
  final input = ReportAdapter.build(
    financeSettings: _settings(),
    receipts: receipts,
    expenseCategories: [
      ExpenseCategory(
          id: 'c1',
          name: 'Toner',
          group: ExpenseCategory.groupDirect,
          createdAt: DateTime(2026, 1, 1)),
    ],
    expenses: expenses,
  );
  return ReportEngine.generate(input, _period,
      generatedAt: DateTime(2026, 11, 26, 10, 30), appVersion: '1.0.0');
}

List<int> _bytes(ReportData d) => ReportWorkbook.build(
      d,
      businessName: 'Printiverse',
      address: 'Enugu',
      phone: '0800',
      currencySymbol: '₦',
    );

void main() {
  const baseSheets = [
    'Summary',
    'Sales',
    'Expenses',
    'P&L',
    'Cashflow',
    'Receivables',
    'Fixed Assets & Depreciation',
    'Loans',
    'Filing Figures',
    'Notes & Assumptions',
  ];

  test('builds a workbook with the ten standard sheets and no unmatched sheet', () {
    final d = _report(
      [_sale('ZKb01', DateTime(2026, 11, 2), total: 5000, deposit: 2000, balance: 3000)],
      expenses: [
        Expense(
          id: 'e1',
          date: DateTime(2026, 11, 3),
          createdAt: DateTime(2026, 11, 3),
          amount: 1200,
          categoryId: 'c1',
          categoryType: ExpenseCategory.groupDirect,
          paidFrom: 'Cash',
          createdByRole: Expense.roleManager,
        ),
      ],
    );
    final bytes = _bytes(d);
    expect(bytes, isNotEmpty);

    final book = Excel.decodeBytes(bytes);
    final names = book.tables.keys.toList();
    expect(names.length, baseSheets.length);
    expect(names, containsAll(baseSheets));
    expect(names, isNot(contains('Sheet1')));
    expect(names, isNot(contains('Unmatched Balance Payments')));
  });

  test('adds the Unmatched sheet only when something is unmatched', () {
    final d = _report([
      _sale('ZKb01', DateTime(2026, 11, 2), total: 5000, deposit: 2000, balance: 3000),
      _sale('ZKb02', DateTime(2026, 11, 4),
          total: 1000, deposit: 1000, balance: 0, items: ['Balance ZKz99']),
    ]);
    expect(d.unmatched.isNotEmpty, isTrue);

    final book = Excel.decodeBytes(_bytes(d));
    expect(book.tables.keys, contains('Unmatched Balance Payments'));
    expect(book.tables.length, baseSheets.length + 1);
  });

  test('an empty period still builds', () {
    final d = _report(const []);
    final book = Excel.decodeBytes(_bytes(d));
    expect(book.tables.keys, containsAll(baseSheets));
  });

  test('works without a currency symbol', () {
    final d = _report(const []);
    final bytes = ReportWorkbook.build(d, businessName: 'Shop');
    expect(bytes, isNotEmpty);
  });

  test('file name carries the period', () {
    final d = _report(const []);
    expect(ReportWorkbook.fileName(d),
        'Financial_Report_2026-11-01_to_2026-11-30.xlsx');
  });
}
