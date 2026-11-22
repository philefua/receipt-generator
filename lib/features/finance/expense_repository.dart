import 'package:hive/hive.dart';

import 'expense_totals.dart';
import 'finance_boxes.dart';
import 'finance_repository.dart';
import 'models/expense.dart';
import 'models/expense_category.dart';

/// Reads and writes expenses. Uses only the `hive` package so it can be tested
/// directly. Rules enforced here (not only in the screens):
///  - amount must be above zero, rounded to 2 places
///  - category must exist and not be archived
///  - no edit and no delete; the only change allowed is voiding
///  - a cashier entry is refused when the manager switched cashier logging off
class ExpenseRepository {
  ExpenseRepository._();
  static final ExpenseRepository instance = ExpenseRepository._();

  Box<Expense>? get box {
    try {
      return Hive.isBoxOpen(FinanceBoxes.expensesBox)
          ? Hive.box<Expense>(FinanceBoxes.expensesBox)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// True when expenses can be saved and read on this device.
  bool get isReady => box != null && FinanceRepository.instance.isReady;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Saves a new expense. Returns an error message, or null on success.
  Future<String?> addExpense({
    required DateTime date,
    required String categoryId,
    required double amount,
    required String paidFrom,
    String description = '',
    String? vendor,
    double? inputVat,
    double? whtAmount,
    required String role,
    DateTime? now,
  }) async {
    final b = box;
    if (b == null) return 'Expenses are not available on this device.';
    final catBox = FinanceRepository.instance.expenseCategoryBox;
    if (catBox == null) return 'Categories are not available on this device.';

    final clock = now ?? DateTime.now();
    if (role != Expense.roleCashier && role != Expense.roleManager) {
      return 'Unknown role.';
    }
    if (role == Expense.roleCashier &&
        !FinanceRepository.instance.settings.allowCashierExpenses) {
      return 'Logging expenses is switched off for cashiers.';
    }
    if (amount.isNaN || amount.isInfinite || amount <= 0) {
      return 'Enter an amount above zero.';
    }
    final rounded = double.parse(amount.toStringAsFixed(2));
    if (rounded <= 0) return 'Enter an amount above zero.';

    final day = dateOnly(date);
    if (day.isAfter(dateOnly(clock))) return 'The date cannot be in the future.';

    final cat = catBox.get(categoryId);
    if (cat == null) return 'Choose a category.';
    if (cat.archived) return 'That category is archived. Choose another.';
    if (role == Expense.roleCashier && cat.group == ExpenseCategory.groupNotInPnl) {
      return 'That category can only be used by the manager.';
    }

    final pf = paidFrom.trim();
    if (pf.isEmpty) return 'Choose how it was paid.';

    if (inputVat != null && inputVat < 0) return 'Input VAT cannot be negative.';
    if (whtAmount != null && whtAmount < 0) return 'WHT cannot be negative.';

    final v = vendor?.trim();
    var stamp = clock.microsecondsSinceEpoch;
    while (b.containsKey('exp_$stamp')) {
      stamp++;
    }
    final id = 'exp_$stamp';
    await b.put(
      id,
      Expense(
        id: id,
        date: day,
        createdAt: clock,
        amount: rounded,
        categoryId: cat.id,
        categoryType: cat.group,
        paidFrom: pf,
        description: description.trim(),
        vendor: (v == null || v.isEmpty) ? null : v,
        inputVat: inputVat == null ? null : double.parse(inputVat.toStringAsFixed(2)),
        whtAmount:
            whtAmount == null ? null : double.parse(whtAmount.toStringAsFixed(2)),
        createdByRole: role,
      ),
    );
    return null;
  }

  /// Voids an expense (manager only). The reason is required. The record stays
  /// in storage and is excluded from totals. Returns an error or null.
  Future<String?> voidExpense(Expense e, String reason, {DateTime? now}) async {
    final r = reason.trim();
    if (r.isEmpty) return 'Enter a reason for voiding.';
    if (e.isVoided) return 'This expense is already voided.';
    e.voidedAt = now ?? DateTime.now();
    e.voidReason = r;
    e.voidedBy = Expense.roleManager;
    await e.save();
    return null;
  }

  /// Manager list. Newest day first. Dates are inclusive. Voided entries are
  /// included (shown struck-through); callers that total use [computeTotals],
  /// which skips them.
  List<Expense> query({DateTime? from, DateTime? to, String? categoryId}) {
    final b = box;
    if (b == null) return const [];
    final f = from == null ? null : dateOnly(from);
    final t = to == null ? null : dateOnly(to);
    final list = b.values.where((e) {
      if (f != null && e.date.isBefore(f)) return false;
      if (t != null && e.date.isAfter(t)) return false;
      if (categoryId != null && e.categoryId != categoryId) return false;
      return true;
    }).toList()
      ..sort((a, c) {
        final d = c.date.compareTo(a.date);
        return d != 0 ? d : c.createdAt.compareTo(a.createdAt);
      });
    return list;
  }

  /// What a cashier may see: expenses entered today by a cashier. Nothing else.
  List<Expense> enteredTodayByCashier({DateTime? now}) {
    final b = box;
    if (b == null) return const [];
    final today = dateOnly(now ?? DateTime.now());
    final list = b.values
        .where((e) =>
            e.createdByRole == Expense.roleCashier &&
            dateOnly(e.createdAt) == today)
        .toList()
      ..sort((a, c) => c.createdAt.compareTo(a.createdAt));
    return list;
  }

  ExpenseTotals totals(Iterable<Expense> expenses) => computeTotals(expenses);
}

extension ExpenseCategoryLookup on ExpenseRepository {
  /// Display name for a category id. Categories are never deleted, so this
  /// only falls back when the categories box is unavailable.
  String categoryName(String id) =>
      FinanceRepository.instance.expenseCategoryBox?.get(id)?.name ?? 'Unknown category';
}
