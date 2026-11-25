// What the report engine returns. Pure Dart, plain values, whole minor units.
// The screen and the Excel file are both built from this one object, so they
// can never disagree.

// ---- Sales -----------------------------------------------------------------

class SalesRow {
  final DateTime date;
  final String code;
  final String customerName;
  final String itemsSummary;
  final int totalMinor;
  final int discountMinor;
  final int depositMinor;
  final int balanceAtTimeMinor;

  /// What this receipt adds to sales. Less than [totalMinor] for a receipt
  /// that also paid an old balance.
  final int revenueMinor;

  /// Paid, Settled later, Owing, Includes old balance payment, or Possible
  /// balance payment (unmatched).
  final String status;

  const SalesRow({
    required this.date,
    required this.code,
    required this.customerName,
    required this.itemsSummary,
    required this.totalMinor,
    required this.discountMinor,
    required this.depositMinor,
    required this.balanceAtTimeMinor,
    required this.revenueMinor,
    required this.status,
  });
}

/// Sales for one day or one month.
class SalesBucket {
  final DateTime key;
  final int count;
  final int revenueMinor;
  final int discountMinor;
  final int depositMinor;

  const SalesBucket({
    required this.key,
    required this.count,
    required this.revenueMinor,
    required this.discountMinor,
    required this.depositMinor,
  });
}

class SalesSection {
  final List<SalesRow> rows;
  final List<SalesBucket> byDay;
  final List<SalesBucket> byMonth;
  final int count;
  final int revenueMinor;
  final int discountMinor;
  final int depositMinor;

  const SalesSection({
    required this.rows,
    required this.byDay,
    required this.byMonth,
    required this.count,
    required this.revenueMinor,
    required this.discountMinor,
    required this.depositMinor,
  });
}

// ---- Expenses --------------------------------------------------------------

class ExpenseRowData {
  final DateTime date;
  final String categoryName;
  final String group;
  final int amountMinor;
  final String paidFrom;
  final String? vendor;
  final int? inputVatMinor;
  final int? whtMinor;
  final String description;
  final String enteredBy;
  final bool voided;
  final String? voidReason;

  const ExpenseRowData({
    required this.date,
    required this.categoryName,
    required this.group,
    required this.amountMinor,
    required this.paidFrom,
    this.vendor,
    this.inputVatMinor,
    this.whtMinor,
    this.description = '',
    this.enteredBy = '',
    this.voided = false,
    this.voidReason,
  });
}

class CategoryTotal {
  final String categoryId;
  final String name;
  final String group;
  final int amountMinor;
  final int count;

  const CategoryTotal({
    required this.categoryId,
    required this.name,
    required this.group,
    required this.amountMinor,
    required this.count,
  });
}

class ExpenseMonth {
  final DateTime month;
  final int directMinor;
  final int operatingMinor;

  const ExpenseMonth({
    required this.month,
    required this.directMinor,
    required this.operatingMinor,
  });

  int get totalMinor => directMinor + operatingMinor;
}

class ExpensesSection {
  /// Direct and operating expenses, not voided, oldest first.
  final List<ExpenseRowData> rows;

  /// Not-in-P&L money (drawings, tax and similar), not voided.
  final List<ExpenseRowData> notInPnlRows;

  /// Voided entries in the period. Shown, never added up.
  final List<ExpenseRowData> voidedRows;
  final List<CategoryTotal> byCategory;
  final List<CategoryTotal> notInPnlByCategory;
  final List<ExpenseMonth> byMonth;
  final int directMinor;
  final int operatingMinor;
  final int notInPnlMinor;

  const ExpensesSection({
    required this.rows,
    required this.notInPnlRows,
    required this.voidedRows,
    required this.byCategory,
    required this.notInPnlByCategory,
    required this.byMonth,
    required this.directMinor,
    required this.operatingMinor,
    required this.notInPnlMinor,
  });

  /// Direct plus operating. Leaves out Not in P&L.
  int get totalMinor => directMinor + operatingMinor;
}

// ---- Profit and loss -------------------------------------------------------

class PnlSection {
  final int revenueMinor;

  /// Written-off balances ("Settle with adjustment") taken in the period.
  final int settlementAdjustmentsMinor;

  /// Direct purchases recorded in the period.
  final int purchasesMinor;

  /// Stock on hand at the start and end, when the stock adjustment applies.
  final int? openingStockMinor;
  final int? closingStockMinor;
  final bool stockAdjusted;

  /// Opening stock + purchases - closing stock when adjusted, else purchases.
  final int directCostsMinor;
  final int grossProfitMinor;
  final int operatingExpensesMinor;
  final int operatingProfitBeforeDepreciationMinor;
  final int depreciationMinor;

  /// Gain (positive) or loss (negative) on assets retired in the period.
  final int disposalGainLossMinor;
  final int operatingProfitMinor;
  final int interestPaidMinor;
  final int netProfitBeforeTaxMinor;

  /// Estimate only: rate x profit, and only when profit is above zero.
  final int estimatedTaxMinor;
  final int netProfitAfterTaxMinor;

  const PnlSection({
    required this.revenueMinor,
    required this.settlementAdjustmentsMinor,
    required this.purchasesMinor,
    required this.openingStockMinor,
    required this.closingStockMinor,
    required this.stockAdjusted,
    required this.directCostsMinor,
    required this.grossProfitMinor,
    required this.operatingExpensesMinor,
    required this.operatingProfitBeforeDepreciationMinor,
    required this.depreciationMinor,
    required this.disposalGainLossMinor,
    required this.operatingProfitMinor,
    required this.interestPaidMinor,
    required this.netProfitBeforeTaxMinor,
    required this.estimatedTaxMinor,
    required this.netProfitAfterTaxMinor,
  });
}

// ---- Cashflow --------------------------------------------------------------

class MethodCash {
  final String method;
  final int inMinor;
  final int outMinor;

  const MethodCash({
    required this.method,
    required this.inMinor,
    required this.outMinor,
  });

  int get netMinor => inMinor - outMinor;
}

class CashflowSection {
  final int openingBalanceMinor;

  /// Money received with sales (deposits and full payments).
  final int salesDepositsMinor;

  /// Money received for earlier sales, through any balance payment.
  final int balancePaymentsMinor;
  final int operatingInMinor;

  /// Direct and operating expenses paid.
  final int expensesPaidMinor;

  /// Not-in-P&L money other than owner drawings (tax remittances and the like).
  final int taxesRemittedMinor;
  final int operatingOutMinor;
  final int netOperatingMinor;
  final int assetPurchasesMinor;
  final int disposalProceedsMinor;
  final int netInvestingMinor;
  final int loansReceivedMinor;
  final int principalRepaidMinor;
  final int interestPaidMinor;
  final int ownerDrawingsMinor;
  final int netFinancingMinor;
  final int netChangeMinor;
  final int closingBalanceMinor;
  final List<MethodCash> byMethod;

  /// True when the opening cash date is after the period starts, so the
  /// opening balance cannot be worked out properly.
  final bool openingCashAfterPeriodStart;

  const CashflowSection({
    required this.openingBalanceMinor,
    required this.salesDepositsMinor,
    required this.balancePaymentsMinor,
    required this.operatingInMinor,
    required this.expensesPaidMinor,
    required this.taxesRemittedMinor,
    required this.operatingOutMinor,
    required this.netOperatingMinor,
    required this.assetPurchasesMinor,
    required this.disposalProceedsMinor,
    required this.netInvestingMinor,
    required this.loansReceivedMinor,
    required this.principalRepaidMinor,
    required this.interestPaidMinor,
    required this.ownerDrawingsMinor,
    required this.netFinancingMinor,
    required this.netChangeMinor,
    required this.closingBalanceMinor,
    required this.byMethod,
    required this.openingCashAfterPeriodStart,
  });

  int get cashInMinor => operatingInMinor + disposalProceedsMinor + loansReceivedMinor;

  int get cashOutMinor =>
      operatingOutMinor +
      assetPurchasesMinor +
      principalRepaidMinor +
      interestPaidMinor +
      ownerDrawingsMinor;
}

// ---- Receivables -----------------------------------------------------------

class ReceivableRow {
  final String code;
  final String customerName;
  final DateTime issuedAt;
  final int totalMinor;

  /// Deposit plus every later payment and write-off.
  final int settledMinor;
  final int outstandingMinor;
  final int ageDays;

  const ReceivableRow({
    required this.code,
    required this.customerName,
    required this.issuedAt,
    required this.totalMinor,
    required this.settledMinor,
    required this.outstandingMinor,
    required this.ageDays,
  });
}

class ReceivablesSection {
  /// Sales that still owed money on the last day of the period, oldest first.
  final List<ReceivableRow> rows;
  final int totalMinor;

  const ReceivablesSection({required this.rows, required this.totalMinor});
}

// ---- Fixed assets ------------------------------------------------------------

class FixedAssetRow {
  final String name;
  final String categoryName;
  final DateTime purchaseDate;
  final int costMinor;

  /// Straight-line or Reducing balance.
  final String method;
  final bool isOpeningBalance;
  final int accumulatedAtStartMinor;
  final int chargeMinor;
  final int accumulatedAtEndMinor;

  /// Cost less depreciation to the end. For a retired asset this is its book
  /// value when it was retired.
  final int netBookValueMinor;

  /// What the asset is worth on the books at the end: zero once retired.
  final int carryingMinor;
  final DateTime? retiredDate;
  final bool retiredInPeriod;

  const FixedAssetRow({
    required this.name,
    required this.categoryName,
    required this.purchaseDate,
    required this.costMinor,
    required this.method,
    required this.isOpeningBalance,
    required this.accumulatedAtStartMinor,
    required this.chargeMinor,
    required this.accumulatedAtEndMinor,
    required this.netBookValueMinor,
    required this.carryingMinor,
    this.retiredDate,
    this.retiredInPeriod = false,
  });
}

class AssetAddition {
  final String name;
  final DateTime purchaseDate;
  final int costMinor;

  /// Equipment already owned: no cash left the business.
  final bool isOpeningBalance;
  final String paymentMethod;

  const AssetAddition({
    required this.name,
    required this.purchaseDate,
    required this.costMinor,
    required this.isOpeningBalance,
    required this.paymentMethod,
  });
}

class AssetDisposal {
  final String name;
  final DateTime date;
  final int proceedsMinor;
  final int nbvAtDisposalMinor;

  /// Proceeds less book value. Negative is a loss.
  final int gainLossMinor;

  const AssetDisposal({
    required this.name,
    required this.date,
    required this.proceedsMinor,
    required this.nbvAtDisposalMinor,
    required this.gainLossMinor,
  });
}

class FixedAssetsSection {
  final List<FixedAssetRow> rows;
  final List<AssetAddition> additions;
  final List<AssetDisposal> disposals;
  final int costMinor;
  final int accumulatedAtStartMinor;

  /// Ties to the depreciation line on the P&L.
  final int chargeMinor;
  final int accumulatedAtEndMinor;
  final int netBookValueMinor;

  /// Ties to the asset net book value on the Summary.
  final int carryingMinor;
  final int additionsCostMinor;

  /// Additions that moved cash. Ties to asset purchases in Cashflow.
  final int additionsCashMinor;

  /// Ties to disposal proceeds in Cashflow.
  final int disposalProceedsMinor;
  final int disposalNbvMinor;

  /// Ties to gain or loss on disposal on the P&L.
  final int disposalGainLossMinor;

  const FixedAssetsSection({
    required this.rows,
    required this.additions,
    required this.disposals,
    required this.costMinor,
    required this.accumulatedAtStartMinor,
    required this.chargeMinor,
    required this.accumulatedAtEndMinor,
    required this.netBookValueMinor,
    required this.carryingMinor,
    required this.additionsCostMinor,
    required this.additionsCashMinor,
    required this.disposalProceedsMinor,
    required this.disposalNbvMinor,
    required this.disposalGainLossMinor,
  });
}

// ---- Loans -------------------------------------------------------------------

class LoanRowData {
  final String lenderName;
  final String lenderType;
  final bool isOpeningBalance;
  final int balanceAtStartMinor;

  /// Cash received in the period. Zero for a loan entered as an opening balance.
  final int receivedMinor;
  final int principalRepaidMinor;
  final int balanceAtEndMinor;
  final int interestPaidMinor;

  /// True when the loan has nothing left to pay at the end.
  final bool settled;

  const LoanRowData({
    required this.lenderName,
    required this.lenderType,
    required this.isOpeningBalance,
    required this.balanceAtStartMinor,
    required this.receivedMinor,
    required this.principalRepaidMinor,
    required this.balanceAtEndMinor,
    required this.interestPaidMinor,
    required this.settled,
  });
}

class LoanRepaymentRow {
  final DateTime date;
  final String lenderName;
  final int principalMinor;
  final int interestMinor;
  final String paymentMethod;
  final String note;

  const LoanRepaymentRow({
    required this.date,
    required this.lenderName,
    required this.principalMinor,
    required this.interestMinor,
    required this.paymentMethod,
    required this.note,
  });
}

class LoansSection {
  final List<LoanRowData> rows;

  /// Repayments dated in the period, not voided, oldest first.
  final List<LoanRepaymentRow> repayments;
  final int balanceAtStartMinor;
  final int receivedMinor;
  final int principalRepaidMinor;
  final int balanceAtEndMinor;

  /// Ties to the interest line on the P&L and in Cashflow.
  final int interestPaidMinor;

  const LoansSection({
    required this.rows,
    required this.repayments,
    required this.balanceAtStartMinor,
    required this.receivedMinor,
    required this.principalRepaidMinor,
    required this.balanceAtEndMinor,
    required this.interestPaidMinor,
  });
}

// ---- Filing figures ----------------------------------------------------------

class FilingSection {
  static const String disclaimer =
      'Prepared figures for your accountant or tax filing. This is not a '
      'completed tax return. Book depreciation differs from tax capital '
      'allowances; give your accountant the Fixed Assets sheet.';

  final int turnoverMinor;
  final int directCostsMinor;
  final int operatingExpensesMinor;
  final int bookDepreciationMinor;
  final int interestPaidMinor;
  final int disposalGainLossMinor;
  final int netProfitBeforeTaxMinor;
  final bool vatEnabled;
  final double vatRatePercent;

  /// Null when VAT is not switched on.
  final int? vatCollectedMinor;

  /// VAT noted on expenses that are not voided. Information only.
  final int inputVatPaidMinor;

  /// VAT collected less input VAT. Null when VAT is not switched on.
  final int? vatPayableMinor;

  /// Null when no tax rate is set.
  final int? estimatedTaxMinor;
  final int receivablesMinor;

  /// Latest stock count on or before the end of the period, if any.
  final int? closingStockMinor;
  final int assetNetBookValueMinor;
  final int loansOutstandingMinor;

  const FilingSection({
    required this.turnoverMinor,
    required this.directCostsMinor,
    required this.operatingExpensesMinor,
    required this.bookDepreciationMinor,
    required this.interestPaidMinor,
    required this.disposalGainLossMinor,
    required this.netProfitBeforeTaxMinor,
    required this.vatEnabled,
    required this.vatRatePercent,
    required this.vatCollectedMinor,
    required this.inputVatPaidMinor,
    required this.vatPayableMinor,
    required this.estimatedTaxMinor,
    required this.receivablesMinor,
    required this.closingStockMinor,
    required this.assetNetBookValueMinor,
    required this.loansOutstandingMinor,
  });
}

// ---- Unmatched balance payments ------------------------------------------------

class UnmatchedRow {
  final String code;
  final DateTime date;
  final String customerName;

  /// Money received on this receipt.
  final int paidMinor;

  /// Why it could not be linked.
  final String reason;

  /// What was written on the receipt.
  final String textSnippet;

  /// Receipt numbers found in that text.
  final String referencesFound;

  /// Up to three sales it might belong to. Never applied automatically.
  final List<String> suggestions;

  /// Dated inside this report's period. Receipts like this stay in sales
  /// until they are linked.
  final bool inPeriod;

  const UnmatchedRow({
    required this.code,
    required this.date,
    required this.customerName,
    required this.paidMinor,
    required this.reason,
    required this.textSnippet,
    required this.referencesFound,
    required this.suggestions,
    required this.inPeriod,
  });
}

class UnmatchedSection {
  /// Every old balance receipt still waiting to be linked, oldest first. The
  /// workbook only gets this sheet when the list is not empty.
  final List<UnmatchedRow> rows;

  const UnmatchedSection({required this.rows});

  bool get isNotEmpty => rows.isNotEmpty;
  int get count => rows.length;
}

// ---- Notes ------------------------------------------------------------------

class NotesSection {
  final DateTime? generatedAt;
  final String appVersion;

  /// How figures are recognised (fixed wording).
  final List<String> basis;

  /// Things about this particular report the reader should know.
  final List<String> notes;

  const NotesSection({
    required this.generatedAt,
    required this.appVersion,
    required this.basis,
    required this.notes,
  });
}

// ---- Summary and whole report ----------------------------------------------

class SummarySection {
  final int totalSalesMinor;
  final int balancePaymentsCollectedMinor;
  final int totalExpensesMinor;
  final int depreciationMinor;
  final int interestPaidMinor;
  final int grossProfitMinor;

  /// Net profit before tax, the same figure as on the P&L.
  final int netProfitMinor;
  final int estimatedTaxMinor;
  final int netProfitAfterTaxMinor;
  final int cashInMinor;
  final int cashOutMinor;
  final int cashNetMinor;
  final int receivablesMinor;
  final int assetNetBookValueMinor;
  final int loansOutstandingMinor;
  final List<CategoryTotal> topCategories;

  /// Old balance receipts still waiting to be linked.
  final int unmatchedCount;

  const SummarySection({
    required this.totalSalesMinor,
    required this.balancePaymentsCollectedMinor,
    required this.totalExpensesMinor,
    required this.depreciationMinor,
    required this.interestPaidMinor,
    required this.grossProfitMinor,
    required this.netProfitMinor,
    required this.estimatedTaxMinor,
    required this.netProfitAfterTaxMinor,
    required this.cashInMinor,
    required this.cashOutMinor,
    required this.cashNetMinor,
    required this.receivablesMinor,
    required this.assetNetBookValueMinor,
    required this.loansOutstandingMinor,
    required this.topCategories,
    required this.unmatchedCount,
  });
}

class ReportData {
  final DateTime from;
  final DateTime to;
  final String periodLabel;
  final SummarySection summary;
  final SalesSection sales;
  final ExpensesSection expenses;
  final PnlSection pnl;
  final CashflowSection cashflow;
  final ReceivablesSection receivables;
  final FixedAssetsSection fixedAssets;
  final LoansSection loans;
  final FilingSection filing;
  final UnmatchedSection unmatched;
  final NotesSection notes;

  const ReportData({
    required this.from,
    required this.to,
    required this.periodLabel,
    required this.summary,
    required this.sales,
    required this.expenses,
    required this.pnl,
    required this.cashflow,
    required this.receivables,
    required this.fixedAssets,
    required this.loans,
    required this.filing,
    required this.unmatched,
    required this.notes,
  });
}
