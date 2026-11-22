import 'package:hive/hive.dart';

part 'expense.g.dart';

/// One business expense. Replaces the old workbook-shaped expense that only
/// ever existed on the unmerged branch and the test tablet (typeId 5).
///
/// Amount, date and category are final: a mistake is corrected by voiding
/// (manager only, reason required) and entering a new expense. Nothing is
/// ever deleted. Only the three void fields can change after saving.
@HiveType(typeId: 14)
class Expense extends HiveObject {
  @HiveField(0)
  final String id;

  /// The day the expense was incurred (date only, no time).
  @HiveField(1)
  final DateTime date;

  /// When the entry was saved.
  @HiveField(2)
  final DateTime createdAt;

  /// Money as a double rounded to 2 places, like everything else in the app.
  @HiveField(3)
  final double amount;

  @HiveField(4)
  final String categoryId;

  /// Copied from the category at save time: direct, operating or non_pnl.
  @HiveField(5)
  final String categoryType;

  /// Free text from the manager-editable "paid from" list.
  @HiveField(6)
  final String paidFrom;

  @HiveField(7)
  final String description;

  @HiveField(8)
  final String? vendor;

  /// Informational only. Does not change [amount].
  @HiveField(9)
  final double? inputVat;

  /// Informational only. Does not change [amount].
  @HiveField(10)
  final double? whtAmount;

  /// [roleCashier] or [roleManager], decided by where the entry was made.
  @HiveField(11)
  final String createdByRole;

  @HiveField(12)
  DateTime? voidedAt;

  @HiveField(13)
  String? voidReason;

  @HiveField(14)
  String? voidedBy;

  Expense({
    required this.id,
    required this.date,
    required this.createdAt,
    required this.amount,
    required this.categoryId,
    required this.categoryType,
    required this.paidFrom,
    this.description = '',
    this.vendor,
    this.inputVat,
    this.whtAmount,
    required this.createdByRole,
    this.voidedAt,
    this.voidReason,
    this.voidedBy,
  });

  static const String roleCashier = 'cashier';
  static const String roleManager = 'manager';

  bool get isVoided => voidedAt != null;
}
