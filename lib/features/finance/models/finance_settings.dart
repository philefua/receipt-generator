import 'package:hive/hive.dart';

part 'finance_settings.g.dart';

/// Finance settings kept in their own box so the existing BusinessSettings
/// adapter is never touched. One record, stored under [FinanceSettings.recordKey].
/// Business name, address, phone and currency still come from BusinessSettings.
@HiveType(typeId: 6)
class FinanceSettings extends HiveObject {
  /// Lets the cashier screen show the Log Expense entry.
  @HiveField(0)
  bool allowCashierExpenses;

  /// 1 to 12.
  @HiveField(1)
  int financialYearStartMonth;

  /// Optional tax ID printed on report headers.
  @HiveField(2)
  String taxId;

  /// Whether VAT figures appear in reports.
  @HiveField(3)
  bool vatEnabled;

  /// VAT rate in percent.
  @HiveField(4)
  double vatRatePercent;

  /// Estimated income tax rate in percent. 0 means off.
  @HiveField(5)
  double estimatedTaxRatePercent;

  /// Cash on hand at [openingCashDate], for the Cashflow sheet.
  @HiveField(6)
  double openingCashBalance;

  /// Date the opening cash balance is as at.
  @HiveField(7)
  DateTime? openingCashDate;

  /// Purchases below this suggest recording an expense instead. 0 means off.
  @HiveField(8)
  double capitalisationThreshold;

  /// Daily serial for balance receipts (-B suffix). Kept apart from the sale counter.
  @HiveField(9)
  int balanceReceiptCounter;

  /// Day marker for [balanceReceiptCounter], same encoding as BusinessSettings.lastReceiptCounterDate.
  @HiveField(10)
  int balanceReceiptCounterDate;

  /// Manager-editable "paid from" list.
  @HiveField(11)
  List<String> paidFromOptions;

  /// True once the generic categories were seeded, so renamed or archived ones are never recreated.
  @HiveField(12)
  bool defaultsSeeded;

  FinanceSettings({
    this.allowCashierExpenses = true,
    this.financialYearStartMonth = 1,
    this.taxId = '',
    this.vatEnabled = false,
    this.vatRatePercent = 0,
    this.estimatedTaxRatePercent = 0,
    this.openingCashBalance = 0,
    this.openingCashDate,
    this.capitalisationThreshold = 0,
    this.balanceReceiptCounter = 0,
    this.balanceReceiptCounterDate = 0,
    required this.paidFromOptions,
    this.defaultsSeeded = false,
  });

  static const String recordKey = 'main';

  static const List<String> defaultPaidFrom = [
    'Cash',
    'Bank transfer',
    'POS',
    'Mobile money',
  ];
}
