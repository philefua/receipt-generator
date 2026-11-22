import 'package:hive/hive.dart';

part 'loan.g.dart';

/// A loan received. Cash in (financing) and a liability, never income.
/// Outstanding balance is computed from repayments, never stored.
@HiveType(typeId: 12)
class Loan extends HiveObject {
  /// Unique id.
  @HiveField(0)
  final String id;

  /// Who lent the money.
  @HiveField(1)
  final String lenderName;

  /// bank, individual, cooperative or other.
  @HiveField(2)
  final String lenderType;

  /// Date received (or the entry date for an opening balance).
  @HiveField(3)
  final DateTime dateReceived;

  /// Amount received, or the outstanding balance for an opening-balance loan.
  @HiveField(4)
  final double principal;

  /// Informational only.
  @HiveField(5)
  final double? interestRatePercent;

  /// Informational only.
  @HiveField(6)
  final int? termMonths;

  /// Payment method or account the money went into.
  @HiveField(7)
  final String receivedInto;

  /// Purpose or notes.
  @HiveField(8)
  final String notes;

  /// Existed before the app was used. No cash inflow is recorded.
  @HiveField(9)
  final bool isOpeningBalance;

  /// When the loan was entered.
  @HiveField(10)
  final DateTime createdAt;

  /// Set when voided.
  @HiveField(11)
  DateTime? voidedAt;

  /// Why it was voided.
  @HiveField(12)
  String? voidReason;

  Loan({
    required this.id,
    required this.lenderName,
    required this.lenderType,
    required this.dateReceived,
    required this.principal,
    this.interestRatePercent,
    this.termMonths,
    required this.receivedInto,
    this.notes = '',
    this.isOpeningBalance = false,
    required this.createdAt,
    this.voidedAt,
    this.voidReason,
  });

  static const List<String> lenderTypes = ['bank', 'individual', 'cooperative', 'other'];
}
