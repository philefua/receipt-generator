import 'package:hive/hive.dart';

part 'loan_transaction.g.dart';

/// One repayment, split into principal and interest as on the lender's statement.
/// The app never calculates interest.
@HiveType(typeId: 13)
class LoanTransaction extends HiveObject {
  /// Unique id.
  @HiveField(0)
  final String id;

  /// Loan id.
  @HiveField(1)
  final String loanId;

  /// Date paid.
  @HiveField(2)
  final DateTime date;

  /// Part that reduces the loan. Not an expense.
  @HiveField(3)
  final double principalAmount;

  /// Finance cost in the P&L.
  @HiveField(4)
  final double interestAmount;

  /// How it was paid.
  @HiveField(5)
  final String paymentMethod;

  /// Optional note.
  @HiveField(6)
  final String note;

  /// When it was entered.
  @HiveField(7)
  final DateTime createdAt;

  /// Set when voided.
  @HiveField(8)
  DateTime? voidedAt;

  /// Why it was voided.
  @HiveField(9)
  String? voidReason;

  LoanTransaction({
    required this.id,
    required this.loanId,
    required this.date,
    this.principalAmount = 0,
    this.interestAmount = 0,
    required this.paymentMethod,
    this.note = '',
    required this.createdAt,
    this.voidedAt,
    this.voidReason,
  });
}
