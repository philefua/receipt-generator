import 'package:hive/hive.dart';

part 'stock_count.g.dart';

/// An optional count of consumables on hand, used for the stock adjustment in the P&L.
@HiveType(typeId: 10)
class StockCount extends HiveObject {
  /// Unique id.
  @HiveField(0)
  final String id;

  /// Day of the count.
  @HiveField(1)
  final DateTime date;

  /// Value of consumables on hand.
  @HiveField(2)
  final double value;

  /// Optional note.
  @HiveField(3)
  final String note;

  /// When the count was entered.
  @HiveField(4)
  final DateTime createdAt;

  StockCount({
    required this.id,
    required this.date,
    required this.value,
    this.note = '',
    required this.createdAt,
  });
}
