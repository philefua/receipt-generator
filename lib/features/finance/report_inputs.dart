import 'depreciation.dart';
import 'legacy_balance_resolver.dart';
import 'loan_math.dart';

/// Plain records the report engine reads. Pure Dart: a later adapter builds
/// them from Hive. All money is whole minor units (amount x 100).
///
/// The adapter is also where old data is tidied. A receipt whose deposit and
/// balance owed were both saved as zero should be given a deposit equal to its
/// total, so it is not read as unpaid.

class ReportSettings {
  /// 1 to 12.
  final int financialYearStartMonth;
  final bool vatEnabled;

  /// VAT rate in percent. Receipt totals are taken to include VAT.
  final double vatRatePercent;

  /// Estimated income tax rate in percent. 0 means off.
  final double estimatedTaxRatePercent;

  /// Cash on hand at the start of [openingCashDate].
  final int openingCashMinor;
  final DateTime? openingCashDate;

  const ReportSettings({
    this.financialYearStartMonth = 1,
    this.vatEnabled = false,
    this.vatRatePercent = 0,
    this.estimatedTaxRatePercent = 0,
    this.openingCashMinor = 0,
    this.openingCashDate,
  });
}

/// A finalised receipt: a sale, or a balance payment made with the app's
/// balance-payment feature.
class ReportReceipt {
  final String code;
  final DateTime issuedAt;

  /// True for receipts made by the balance-payment feature (-B codes).
  final bool isBalancePayment;

  /// For a balance payment: the sale it pays towards.
  final String? linkedCode;
  final String customerName;
  final String itemsSummary;
  final int totalMinor;
  final int discountMinor;
  final int depositMinor;

  /// What was still owed when the receipt was issued.
  final int balanceAtTimeMinor;
  final String paymentMethod;

  const ReportReceipt({
    required this.code,
    required this.issuedAt,
    this.isBalancePayment = false,
    this.linkedCode,
    this.customerName = '',
    this.itemsSummary = '',
    required this.totalMinor,
    this.discountMinor = 0,
    required this.depositMinor,
    this.balanceAtTimeMinor = 0,
    this.paymentMethod = '',
  });
}

class ReportExpense {
  final String id;
  final DateTime date;
  final String categoryId;
  final String categoryName;

  /// direct, operating or non_pnl.
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

  const ReportExpense({
    required this.id,
    required this.date,
    required this.categoryId,
    required this.categoryName,
    required this.group,
    required this.amountMinor,
    this.paidFrom = '',
    this.vendor,
    this.inputVatMinor,
    this.whtMinor,
    this.description = '',
    this.enteredBy = '',
    this.voided = false,
    this.voidReason,
  });
}

/// An active (not voided) write-off from "Settle with adjustment".
class ReportWriteoff {
  final String receiptCode;

  /// The day it was recorded.
  final DateTime date;
  final int amountMinor;
  final String reason;

  const ReportWriteoff({
    required this.receiptCode,
    required this.date,
    required this.amountMinor,
    this.reason = '',
  });
}

class ReportStockCount {
  final DateTime date;
  final int valueMinor;
  const ReportStockCount({required this.date, required this.valueMinor});
}

class ReportAsset {
  final String id;
  final String name;
  final String categoryName;

  /// Cost, residual, life, method, retirement and voided state.
  final AssetSpec spec;

  /// Owned before the app was used: no cash outflow.
  final bool isOpeningBalance;
  final String paymentMethod;

  const ReportAsset({
    required this.id,
    required this.name,
    this.categoryName = '',
    required this.spec,
    this.isOpeningBalance = false,
    this.paymentMethod = '',
  });
}

class ReportLoan {
  final String id;
  final String lenderName;
  final String lenderType;
  final LoanSpec spec;

  /// Existed before the app was used: no cash inflow.
  final bool isOpeningBalance;
  final String receivedInto;

  const ReportLoan({
    required this.id,
    required this.lenderName,
    this.lenderType = '',
    required this.spec,
    this.isOpeningBalance = false,
    this.receivedInto = '',
  });
}

class ReportRepayment {
  final RepaymentSpec spec;
  final String paymentMethod;
  final String note;

  const ReportRepayment({
    required this.spec,
    this.paymentMethod = '',
    this.note = '',
  });
}

class ReportInput {
  final ReportSettings settings;
  final List<ReportReceipt> receipts;
  final List<ReportExpense> expenses;
  final List<ReportWriteoff> writeoffs;
  final List<ReportStockCount> stockCounts;
  final List<ReportAsset> assets;
  final List<ReportLoan> loans;
  final List<ReportRepayment> repayments;

  /// The result of matching old typed balance receipts to their sales, from
  /// [LegacyBalanceResolver.resolve].
  final LegacyResolution legacy;

  const ReportInput({
    this.settings = const ReportSettings(),
    this.receipts = const [],
    this.expenses = const [],
    this.writeoffs = const [],
    this.stockCounts = const [],
    this.assets = const [],
    this.loans = const [],
    this.repayments = const [],
    this.legacy = const LegacyResolution(entries: [], baseOutstanding: {}),
  });
}
