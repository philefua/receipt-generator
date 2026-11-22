import 'package:hive/hive.dart';

part 'expense_category.g.dart';

/// A manager-editable expense category. Never deleted once created: archiving only hides it from the picker.
@HiveType(typeId: 7)
class ExpenseCategory extends HiveObject {
  /// Unique id. Seeded categories use fixed ids so seeding is idempotent.
  @HiveField(0)
  final String id;

  /// Display name.
  @HiveField(1)
  String name;

  /// One of [groupDirect], [groupOperating], [groupNotInPnl]. Never changed after creation.
  @HiveField(2)
  final String group;

  /// Archived categories are hidden from pickers but stay on old expenses.
  @HiveField(3)
  bool archived;

  /// Position inside its group.
  @HiveField(4)
  int sortOrder;

  /// When the category was created.
  @HiveField(5)
  final DateTime createdAt;

  ExpenseCategory({
    required this.id,
    required this.name,
    required this.group,
    this.archived = false,
    this.sortOrder = 0,
    required this.createdAt,
  });

  static const String groupDirect = 'direct';
  static const String groupOperating = 'operating';
  static const String groupNotInPnl = 'non_pnl';
  static const List<String> groups = [groupDirect, groupOperating, groupNotInPnl];
}
