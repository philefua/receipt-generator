import 'package:hive/hive.dart';

part 'product_preset.g.dart';

@HiveType(typeId: 1)
class ProductPreset extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  double price;

  @HiveField(3)
  String? category;

  @HiveField(4)
  bool isActive;

  ProductPreset({
    required this.id,
    required this.name,
    required this.price,
    this.category,
    this.isActive = true,
  });
}
