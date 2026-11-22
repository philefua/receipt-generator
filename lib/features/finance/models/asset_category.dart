import 'package:hive/hive.dart';

part 'asset_category.g.dart';

/// A fixed-asset category with a placeholder useful life the shop or its accountant should confirm.
@HiveType(typeId: 8)
class AssetCategory extends HiveObject {
  /// Unique id. Seeded categories use fixed ids.
  @HiveField(0)
  final String id;

  /// Display name.
  @HiveField(1)
  String name;

  /// Suggested useful life in months when adding an asset.
  @HiveField(2)
  int defaultUsefulLifeMonths;

  /// Archived categories are hidden from pickers.
  @HiveField(3)
  bool archived;

  /// Display order.
  @HiveField(4)
  int sortOrder;

  /// When the category was created.
  @HiveField(5)
  final DateTime createdAt;

  AssetCategory({
    required this.id,
    required this.name,
    required this.defaultUsefulLifeMonths,
    this.archived = false,
    this.sortOrder = 0,
    required this.createdAt,
  });
}
