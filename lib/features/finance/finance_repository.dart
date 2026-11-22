import 'package:hive/hive.dart';

import 'finance_boxes.dart';
import 'models/asset_category.dart';
import 'models/expense_category.dart';
import 'models/finance_settings.dart';

/// Reads and writes finance settings and categories.
///
/// Uses only the `hive` package (no Flutter), so it can be tested directly.
/// Every getter tolerates a box that failed to open: check [isReady] first.
class FinanceRepository {
  FinanceRepository._();
  static final FinanceRepository instance = FinanceRepository._();

  /// Generic starter categories. A shop adds its own names; nothing here is
  /// specific to any one business. Fixed ids keep seeding idempotent.
  static const List<(String id, String name, String group)> _expenseSeed = [
    ('seed_direct_toner', 'Toner', ExpenseCategory.groupDirect),
    ('seed_direct_ink', 'Ink', ExpenseCategory.groupDirect),
    ('seed_direct_paper', 'Paper', ExpenseCategory.groupDirect),
    ('seed_direct_vinyl', 'Vinyl', ExpenseCategory.groupDirect),
    ('seed_direct_lamination', 'Lamination', ExpenseCategory.groupDirect),
    ('seed_direct_outsourced', 'Outsourced printing', ExpenseCategory.groupDirect),
    ('seed_op_rent', 'Rent', ExpenseCategory.groupOperating),
    ('seed_op_power', 'Electricity / power', ExpenseCategory.groupOperating),
    ('seed_op_fuel', 'Fuel / generator', ExpenseCategory.groupOperating),
    ('seed_op_wages', 'Wages', ExpenseCategory.groupOperating),
    ('seed_op_data', 'Data / internet', ExpenseCategory.groupOperating),
    ('seed_op_transport', 'Transport', ExpenseCategory.groupOperating),
    ('seed_op_repairs', 'Repairs / maintenance', ExpenseCategory.groupOperating),
    ('seed_op_bank', 'Bank charges', ExpenseCategory.groupOperating),
    ('seed_op_marketing', 'Marketing', ExpenseCategory.groupOperating),
    ('seed_op_misc', 'Miscellaneous', ExpenseCategory.groupOperating),
    ('seed_np_drawings', 'Owner drawings', ExpenseCategory.groupNotInPnl),
    ('seed_np_tax', 'Tax remittances', ExpenseCategory.groupNotInPnl),
  ];

  /// Placeholder useful lives. The shop or its accountant should confirm them.
  static const List<(String id, String name, int months)> _assetSeed = [
    ('seed_asset_machines', 'Printers and machines', 60),
    ('seed_asset_it', 'Computers and IT', 36),
    ('seed_asset_furniture', 'Furniture and fittings', 60),
    ('seed_asset_power', 'Generators and power equipment', 60),
    ('seed_asset_vehicles', 'Vehicles', 48),
    ('seed_asset_building', 'Building improvements', 120),
  ];

  Box<FinanceSettings>? get _settingsBox => _box<FinanceSettings>(FinanceBoxes.settingsBox);
  Box<ExpenseCategory>? get _expenseCats =>
      _box<ExpenseCategory>(FinanceBoxes.expenseCategoriesBox);
  Box<AssetCategory>? get _assetCats =>
      _box<AssetCategory>(FinanceBoxes.assetCategoriesBox);

  Box<T>? _box<T>(String name) {
    try {
      return Hive.isBoxOpen(name) ? Hive.box<T>(name) : null;
    } catch (_) {
      return null;
    }
  }

  /// True when the settings and category boxes are usable.
  bool get isReady =>
      _settingsBox != null && _expenseCats != null && _assetCats != null;

  Box<ExpenseCategory>? get expenseCategoryBox => _expenseCats;
  Box<AssetCategory>? get assetCategoryBox => _assetCats;

  /// Creates the settings record and seeds the generic categories once.
  Future<void> initialize() async {
    final box = _settingsBox;
    if (box == null) return;
    var s = box.get(FinanceSettings.recordKey);
    if (s == null) {
      s = FinanceSettings(
        paidFromOptions: List<String>.of(FinanceSettings.defaultPaidFrom),
      );
      await box.put(FinanceSettings.recordKey, s);
    }
    if (!s.defaultsSeeded) {
      final eBox = _expenseCats;
      final aBox = _assetCats;
      if (eBox == null || aBox == null) return;
      final now = DateTime.now();
      var order = 0;
      for (final c in _expenseSeed) {
        if (!eBox.containsKey(c.$1)) {
          await eBox.put(
            c.$1,
            ExpenseCategory(
                id: c.$1, name: c.$2, group: c.$3, sortOrder: order, createdAt: now),
          );
        }
        order++;
      }
      order = 0;
      for (final c in _assetSeed) {
        if (!aBox.containsKey(c.$1)) {
          await aBox.put(
            c.$1,
            AssetCategory(
                id: c.$1,
                name: c.$2,
                defaultUsefulLifeMonths: c.$3,
                sortOrder: order,
                createdAt: now),
          );
        }
        order++;
      }
      s.defaultsSeeded = true;
      await s.save();
    }
  }

  /// The settings record. Falls back to an unsaved default if the box is not
  /// available, so callers never crash.
  FinanceSettings get settings {
    final s = _settingsBox?.get(FinanceSettings.recordKey);
    return s ??
        FinanceSettings(
          paidFromOptions: List<String>.of(FinanceSettings.defaultPaidFrom),
        );
  }

  Future<void> saveSettings(FinanceSettings s) async {
    final box = _settingsBox;
    if (box == null) {
      throw StateError('Finance settings are not available on this device.');
    }
    await box.put(FinanceSettings.recordKey, s);
  }

  // ---- Expense categories ------------------------------------------------

  /// All categories of one group in display order, optionally hiding archived.
  List<ExpenseCategory> expenseCategories(
    String group, {
    bool includeArchived = true,
  }) {
    final box = _expenseCats;
    if (box == null) return const [];
    final list = box.values
        .where((c) => c.group == group && (includeArchived || !c.archived))
        .toList()
      ..sort((a, b) {
        final o = a.sortOrder.compareTo(b.sortOrder);
        return o != 0 ? o : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  bool _nameTaken(String name, String group, {String? exceptId}) {
    final box = _expenseCats;
    if (box == null) return false;
    final n = name.trim().toLowerCase();
    return box.values.any(
      (c) => c.group == group && c.id != exceptId && c.name.trim().toLowerCase() == n,
    );
  }

  /// Adds a category. Returns an error message, or null on success.
  Future<String?> addExpenseCategory(String name, String group) async {
    final box = _expenseCats;
    if (box == null) return 'Categories are not available on this device.';
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a name.';
    if (!ExpenseCategory.groups.contains(group)) return 'Choose a group.';
    if (_nameTaken(trimmed, group)) return 'That name already exists in this group.';
    final now = DateTime.now();
    final nextOrder = box.values
            .where((c) => c.group == group)
            .fold<int>(-1, (m, c) => c.sortOrder > m ? c.sortOrder : m) +
        1;
    final id = 'cat_${now.microsecondsSinceEpoch}';
    await box.put(
      id,
      ExpenseCategory(
          id: id, name: trimmed, group: group, sortOrder: nextOrder, createdAt: now),
    );
    return null;
  }

  /// Renames a category. Returns an error message, or null on success.
  Future<String?> renameExpenseCategory(ExpenseCategory c, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a name.';
    if (_nameTaken(trimmed, c.group, exceptId: c.id)) {
      return 'That name already exists in this group.';
    }
    c.name = trimmed;
    await c.save();
    return null;
  }

  /// Archives or restores a category. Categories are never deleted.
  Future<void> setExpenseCategoryArchived(ExpenseCategory c, bool archived) async {
    c.archived = archived;
    await c.save();
  }

  // ---- Paid-from list ----------------------------------------------------

  /// Adds a "paid from" option. Returns an error message, or null on success.
  Future<String?> addPaidFrom(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Enter a name.';
    final s = settings;
    if (s.paidFromOptions.any((o) => o.toLowerCase() == trimmed.toLowerCase())) {
      return 'That option already exists.';
    }
    s.paidFromOptions = [...s.paidFromOptions, trimmed];
    await saveSettings(s);
    return null;
  }

  /// Removes an option from the list. Old records keep their stored text.
  Future<String?> removePaidFrom(String name) async {
    final s = settings;
    if (s.paidFromOptions.length <= 1) return 'Keep at least one option.';
    s.paidFromOptions = s.paidFromOptions.where((o) => o != name).toList();
    await saveSettings(s);
    return null;
  }
}
