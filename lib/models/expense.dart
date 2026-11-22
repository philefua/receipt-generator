import 'package:hive/hive.dart';

part 'expense.g.dart';

/// One expense row, shaped to map onto tab `3_Expense_Ledger` of the
/// Printiverse financial workbook (columns A to N).
///
/// Nothing is ever hard-deleted: a mistaken entry is marked [isVoided],
/// which removes it from totals and from the export but keeps the record
/// (and its voucher number) in the app.
///
/// "Total Cash Paid" (ledger column J) is never stored. It is always
/// calculated as Net + Input VAT - WHT, see [totalCashPaid].
@HiveType(typeId: 5)
class Expense extends HiveObject {
  /// Internal unique id (not exported).
  @HiveField(0)
  final String id;

  /// Ledger A: the date the expense happened.
  @HiveField(1)
  final DateTime date;

  /// Ledger B: auto-numbered voucher, e.g. EXP-0001.
  @HiveField(2)
  final String voucher;

  /// Ledger C: who was paid.
  @HiveField(3)
  final String vendor;

  /// Ledger D: what was bought, with quantity.
  @HiveField(4)
  final String description;

  /// Ledger E: COGS, OpEx, CapEx, Tax Remittance, Drawings or Loan Repayment.
  @HiveField(5)
  final String costType;

  /// Ledger F: must belong to [costType] (see ExpenseOptions).
  @HiveField(6)
  final String category;

  /// Ledger G: amount before VAT and before WHT. For Tax Remittance,
  /// Drawings and Loan Repayment, the amount paid.
  @HiveField(7)
  final double netAmount;

  /// Ledger H: input VAT paid (0 if none).
  @HiveField(8)
  final double inputVat;

  /// Ledger I: WHT withheld from the vendor (0 if none).
  @HiveField(9)
  final double whtDeducted;

  /// Ledger K: Business Bank, Petty Cash, POS / Till Cash or Mobile Money.
  @HiveField(10)
  final String paymentAccount;

  /// Ledger L: Attached (Drive), Physical Receipt, Payroll Schedule or
  /// No Receipt (Missing).
  @HiveField(11)
  final String receiptStatus;

  /// Ledger M: staff name.
  @HiveField(12)
  final String recordedBy;

  /// Ledger N: serial number or asset tag (required for CapEx).
  @HiveField(13)
  final String notes;

  /// True once the entry has been voided. The only field that can change.
  @HiveField(14)
  bool isVoided;

  /// When the entry was typed in (audit trail, not exported).
  @HiveField(15)
  final DateTime recordedAt;

  Expense({
    required this.id,
    required this.date,
    required this.voucher,
    required this.vendor,
    required this.description,
    required this.costType,
    required this.category,
    required this.netAmount,
    this.inputVat = 0,
    this.whtDeducted = 0,
    required this.paymentAccount,
    required this.receiptStatus,
    this.recordedBy = '',
    this.notes = '',
    this.isVoided = false,
    required this.recordedAt,
  });

  /// Ledger J: Net + Input VAT - WHT, rounded to 2 decimal places.
  double get totalCashPaid =>
      double.parse((netAmount + inputVat - whtDeducted).toStringAsFixed(2));
}
