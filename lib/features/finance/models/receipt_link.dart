import 'package:hive/hive.dart';

part 'receipt_link.g.dart';

/// A manual link or write-off that lives beside a receipt, never on it.
/// Receipts are immutable, so legacy balance links and "Settle with adjustment"
/// records are stored here.
@HiveType(typeId: 9)
class ReceiptLink extends HiveObject {
  /// Unique id.
  @HiveField(0)
  final String id;

  /// [kindLink] or [kindWriteoff].
  @HiveField(1)
  final String kind;

  /// The balance receipt being linked, or the receipt being written off.
  @HiveField(2)
  final String receiptCode;

  /// The original sale receipt. Same as [receiptCode] for a write-off.
  @HiveField(3)
  final String originalReceiptCode;

  /// Amount applied to the original balance, or amount written off.
  @HiveField(4)
  final double amount;

  /// Required for a write-off, optional note for a link.
  @HiveField(5)
  final String reason;

  /// When the record was made.
  @HiveField(6)
  final DateTime createdAt;

  /// Set when the manager voids the record.
  @HiveField(7)
  DateTime? voidedAt;

  /// Why it was voided.
  @HiveField(8)
  String? voidReason;

  ReceiptLink({
    required this.id,
    required this.kind,
    required this.receiptCode,
    required this.originalReceiptCode,
    required this.amount,
    required this.reason,
    required this.createdAt,
    this.voidedAt,
    this.voidReason,
  });

  static const String kindLink = 'link';
  static const String kindWriteoff = 'writeoff';
}
