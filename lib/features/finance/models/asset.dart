import 'package:hive/hive.dart';

part 'asset.g.dart';

/// A fixed asset. Purchases are recorded here, never as expenses.
/// Depreciation is computed by the report engine, never stored.
/// No edit after save, except retiring and voiding.
@HiveType(typeId: 11)
class Asset extends HiveObject {
  /// Unique id.
  @HiveField(0)
  final String id;

  /// What the asset is.
  @HiveField(1)
  final String name;

  /// AssetCategory id.
  @HiveField(2)
  final String categoryId;

  /// Original purchase date.
  @HiveField(3)
  final DateTime purchaseDate;

  /// Original cost.
  @HiveField(4)
  final double cost;

  /// How it was paid for.
  @HiveField(5)
  final String paymentMethod;

  /// Optional seller.
  @HiveField(6)
  final String? vendor;

  /// Months of useful life.
  @HiveField(7)
  final int usefulLifeMonths;

  /// Value left at the end of its life.
  @HiveField(8)
  final double residualValue;

  /// [methodStraightLine] or [methodReducingBalance].
  @HiveField(9)
  final String method;

  /// Annual rate in percent, reducing balance only.
  @HiveField(10)
  final double? annualRate;

  /// Bought before the shop started using the app. No cash outflow is recorded.
  @HiveField(11)
  final bool isOpeningBalance;

  /// [statusActive] or [statusRetired].
  @HiveField(12)
  String status;

  /// Set when retired.
  @HiveField(13)
  DateTime? retiredDate;

  /// Sale proceeds on retirement, if any.
  @HiveField(14)
  double? disposalProceeds;

  /// Optional notes.
  @HiveField(15)
  final String notes;

  /// When the asset was entered.
  @HiveField(16)
  final DateTime createdAt;

  /// Set when voided.
  @HiveField(17)
  DateTime? voidedAt;

  /// Why it was voided.
  @HiveField(18)
  String? voidReason;

  Asset({
    required this.id,
    required this.name,
    required this.categoryId,
    required this.purchaseDate,
    required this.cost,
    required this.paymentMethod,
    this.vendor,
    required this.usefulLifeMonths,
    this.residualValue = 0,
    this.method = 'straight_line',
    this.annualRate,
    this.isOpeningBalance = false,
    this.status = 'active',
    this.retiredDate,
    this.disposalProceeds,
    this.notes = '',
    required this.createdAt,
    this.voidedAt,
    this.voidReason,
  });

  static const String methodStraightLine = 'straight_line';
  static const String methodReducingBalance = 'reducing_balance';
  static const String statusActive = 'active';
  static const String statusRetired = 'retired';
}
