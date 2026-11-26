import 'package:hive/hive.dart';

import '../../models/receipt.dart';
import 'asset_repository.dart';
import 'balance_math.dart';
import 'balance_repository.dart';
import 'finance_boxes.dart';
import 'finance_repository.dart';
import 'legacy_balance_resolver.dart';
import 'loan_repository.dart';
import 'models/asset.dart';
import 'models/asset_category.dart';
import 'models/expense.dart';
import 'models/expense_category.dart';
import 'models/finance_settings.dart';
import 'models/loan.dart';
import 'models/loan_transaction.dart';
import 'models/receipt_link.dart';
import 'models/stock_count.dart';
import 'report_inputs.dart';
import 'writeoff_totals.dart';

/// Phase 10a: turns the shop's stored records into the [ReportInput] the
/// report engine reads (handoff section 6).
///
/// Two layers:
///  - [ReportAdapter.build] is plain Dart over model objects (no boxes), so it
///    is easy to test.
///  - [ReportAdapter.fromHive] reads the open boxes and calls [build].
///
/// Nothing here writes to any box. Receipts, expenses, assets and loans are
/// only read.
///
/// Old-data tidy: a sale receipt saved with both a zero deposit and a zero
/// balance owed (made before deposits existed) is read as fully paid, with a
/// deposit equal to its total. A receipt with a zero deposit but a balance
/// owed is a real unpaid sale and is left alone. The same tidied figures feed
/// the old-receipt matcher, so the matcher and the engine always agree.
class ReportAdapter {
  ReportAdapter._();

  static const String unknownCategory = 'Unknown category';

  /// Reads the open boxes. Throws [StateError] when receipts or the finance
  /// settings are not available, so a report is never built from nothing.
  static ReportInput fromHive() {
    final receiptsBox = _openBox<Receipt>(BalanceRepository.receiptsBoxName);
    if (receiptsBox == null || !FinanceRepository.instance.isReady) {
      throw StateError('Reports are not available on this device.');
    }

    final links = _openBox<ReceiptLink>(FinanceBoxes.receiptLinksBox)
            ?.values
            .toList() ??
        const <ReceiptLink>[];

    return build(
      financeSettings: FinanceRepository.instance.settings,
      receipts: receiptsBox.values.toList(),
      expenses: _openBox<Expense>(FinanceBoxes.expensesBox)?.values.toList() ??
          const <Expense>[],
      expenseCategories:
          FinanceRepository.instance.expenseCategoryBox?.values.toList() ??
              const <ExpenseCategory>[],
      links: links,
      stockCounts:
          _openBox<StockCount>(FinanceBoxes.stockCountsBox)?.values.toList() ??
              const <StockCount>[],
      assets: AssetRepository.instance.box?.values.toList() ?? const <Asset>[],
      assetCategories:
          FinanceRepository.instance.assetCategoryBox?.values.toList() ??
              const <AssetCategory>[],
      loans: LoanRepository.instance.loanBox?.values.toList() ?? const <Loan>[],
      repayments: LoanRepository.instance.transactionBox?.values.toList() ??
          const <LoanTransaction>[],
      // Same write-off totals the balance screens use.
      writeoffTotals: WriteoffTotals.read(),
    );
  }

  static Box<T>? _openBox<T>(String name) {
    try {
      return Hive.isBoxOpen(name) ? Hive.box<T>(name) : null;
    } catch (_) {
      return null;
    }
  }

  /// Builds the engine input from plain model objects.
  ///
  /// [writeoffTotals] is the minor-unit total written off per sale code. When
  /// it is left out, it is added up from the active write-off records in
  /// [links].
  static ReportInput build({
    required FinanceSettings financeSettings,
    List<Receipt> receipts = const [],
    List<Expense> expenses = const [],
    List<ExpenseCategory> expenseCategories = const [],
    List<ReceiptLink> links = const [],
    List<StockCount> stockCounts = const [],
    List<Asset> assets = const [],
    List<AssetCategory> assetCategories = const [],
    List<Loan> loans = const [],
    List<LoanTransaction> repayments = const [],
    Map<String, int>? writeoffTotals,
  }) {
    final reportReceipts = [for (final r in receipts) _receipt(r)];

    final activeLinks = [
      for (final l in links)
        if (l.kind == ReceiptLink.kindLink && l.voidedAt == null) l,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final activeWriteoffs = [
      for (final l in links)
        if (l.kind == ReceiptLink.kindWriteoff && l.voidedAt == null) l,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final totals = writeoffTotals ?? _sumWriteoffs(activeWriteoffs);

    final legacy = LegacyBalanceResolver.resolve(
      receipts: [
        for (var i = 0; i < receipts.length; i++)
          _legacyRecord(receipts[i], reportReceipts[i]),
      ],
      manualLinks: [
        for (final l in activeLinks)
          ManualLinkRecord(
            id: l.id,
            receiptCode: l.receiptCode,
            originalCode: l.originalReceiptCode,
            appliedMinor: BalanceMath.toMinor(l.amount),
          ),
      ],
      writeoffs: totals,
    );

    final expenseCategoryNames = {
      for (final c in expenseCategories) c.id: c.name,
    };
    final assetCategoryNames = {
      for (final c in assetCategories) c.id: c.name,
    };

    return ReportInput(
      settings: ReportSettings(
        financialYearStartMonth: financeSettings.financialYearStartMonth,
        vatEnabled: financeSettings.vatEnabled,
        vatRatePercent: financeSettings.vatRatePercent,
        estimatedTaxRatePercent: financeSettings.estimatedTaxRatePercent,
        openingCashMinor: BalanceMath.toMinor(financeSettings.openingCashBalance),
        openingCashDate: financeSettings.openingCashDate,
      ),
      receipts: reportReceipts,
      expenses: [
        for (final e in expenses) _expense(e, expenseCategoryNames),
      ],
      writeoffs: [
        for (final l in activeWriteoffs)
          ReportWriteoff(
            receiptCode: l.receiptCode,
            date: l.createdAt,
            amountMinor: BalanceMath.toMinor(l.amount),
            reason: l.reason,
          ),
      ],
      stockCounts: [
        for (final s in stockCounts)
          ReportStockCount(
            date: s.date,
            valueMinor: BalanceMath.toMinor(s.value),
          ),
      ],
      assets: [
        for (final a in assets)
          ReportAsset(
            id: a.id,
            name: a.name,
            categoryName: assetCategoryNames[a.categoryId] ?? unknownCategory,
            spec: AssetRepository.specOf(a),
            isOpeningBalance: a.isOpeningBalance,
            paymentMethod: a.paymentMethod,
          ),
      ],
      loans: [
        for (final l in loans)
          ReportLoan(
            id: l.id,
            lenderName: l.lenderName,
            lenderType: l.lenderType,
            spec: LoanRepository.loanSpec(l),
            isOpeningBalance: l.isOpeningBalance,
            receivedInto: l.receivedInto,
          ),
      ],
      repayments: [
        for (final t in repayments)
          ReportRepayment(
            spec: LoanRepository.repaymentSpec(t),
            paymentMethod: t.paymentMethod,
            note: t.note,
          ),
      ],
      legacy: legacy,
    );
  }

  // ---- receipts --------------------------------------------------------------

  /// Deposit as the report should read it. A sale with a zero deposit and a
  /// zero balance owed is old data and counts as fully paid.
  static int _depositMinor(Receipt r) {
    final total = BalanceMath.toMinor(r.totalPayable);
    final deposit = BalanceMath.toMinor(r.depositPaid);
    final balance = BalanceMath.toMinor(r.balanceOwed);
    if (!r.isBalancePayment && deposit == 0 && balance == 0 && total > 0) {
      return total;
    }
    return deposit;
  }

  static int _balanceAtTimeMinor(Receipt r) {
    final v = BalanceMath.toMinor(r.balanceOwed);
    return v < 0 ? 0 : v;
  }

  static String _itemsSummary(Receipt r) => [
        for (final i in r.items) '${i.name} x${i.quantity}',
      ].join(', ');

  static ReportReceipt _receipt(Receipt r) => ReportReceipt(
        code: r.receiptCode,
        issuedAt: r.issuedAt,
        isBalancePayment: r.isBalancePayment,
        linkedCode: r.linkedReceiptId,
        customerName: r.customerName,
        itemsSummary: _itemsSummary(r),
        totalMinor: BalanceMath.toMinor(r.totalPayable),
        discountMinor: BalanceMath.toMinor(r.discountAmount),
        depositMinor: _depositMinor(r),
        balanceAtTimeMinor: _balanceAtTimeMinor(r),
        paymentMethod: r.paymentMethod,
      );

  /// The matcher reads the same tidied figures as the engine.
  static LegacyReceiptRecord _legacyRecord(Receipt r, ReportReceipt tidy) =>
      LegacyReceiptRecord(
        code: r.receiptCode,
        issuedAt: r.issuedAt,
        isBalanceType: r.isBalancePayment,
        linkedCode: r.linkedReceiptId,
        customerName: r.customerName,
        customerWhatsapp: r.customerWhatsapp,
        itemNames: [for (final i in r.items) i.name],
        couponReference: r.couponReference,
        totalMinor: tidy.totalMinor,
        depositMinor: tidy.depositMinor,
      );

  // ---- expenses --------------------------------------------------------------

  static ReportExpense _expense(Expense e, Map<String, String> names) =>
      ReportExpense(
        id: e.id,
        date: e.date,
        categoryId: e.categoryId,
        categoryName: names[e.categoryId] ?? unknownCategory,
        group: e.categoryType,
        amountMinor: BalanceMath.toMinor(e.amount),
        paidFrom: e.paidFrom,
        vendor: e.vendor,
        inputVatMinor:
            e.inputVat == null ? null : BalanceMath.toMinor(e.inputVat!),
        whtMinor: e.whtAmount == null ? null : BalanceMath.toMinor(e.whtAmount!),
        description: e.description,
        enteredBy: e.createdByRole,
        voided: e.isVoided,
        voidReason: e.voidReason,
      );

  // ---- write-offs ------------------------------------------------------------

  static Map<String, int> _sumWriteoffs(Iterable<ReceiptLink> active) {
    final map = <String, int>{};
    for (final l in active) {
      map[l.receiptCode] =
          (map[l.receiptCode] ?? 0) + BalanceMath.toMinor(l.amount);
    }
    return map;
  }
}
