import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:receipt_generator/features/finance/expense_repository.dart';
import 'package:receipt_generator/features/finance/expense_totals.dart';
import 'package:receipt_generator/features/finance/finance_boxes.dart';
import 'package:receipt_generator/features/finance/finance_repository.dart';
import 'package:receipt_generator/features/finance/models/expense.dart';

void main() {
  late Directory dir;
  final repo = ExpenseRepository.instance;

  Future<String?> add({
    String cat = 'seed_op_rent',
    double amount = 100,
    String paidFrom = 'Cash',
    String role = Expense.roleManager,
    DateTime? date,
    DateTime? now,
    double? vat,
  }) =>
      repo.addExpense(
        date: date ?? DateTime(2026, 11, 22),
        categoryId: cat,
        amount: amount,
        paidFrom: paidFrom,
        role: role,
        now: now ?? DateTime(2026, 11, 22, 10),
        inputVat: vat,
      );

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('expense_test_');
    Hive.init(dir.path);
    FinanceBoxes.registerAdapters();
    await FinanceBoxes.openAll();
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('expense box and typeId 14 are registered and backed up', () {
    expect(Hive.isAdapterRegistered(14), isTrue);
    expect(FinanceBoxes.allBoxNames, contains(FinanceBoxes.expensesBox));
    expect(FinanceBoxes.failures, isEmpty);
    expect(repo.isReady, isTrue);
  });

  test('a saved expense keeps every field after close and reopen', () async {
    expect(
        await repo.addExpense(
          date: DateTime(2026, 11, 20, 15, 45),
          categoryId: 'seed_direct_toner',
          amount: 1234.567,
          paidFrom: 'Bank transfer',
          description: '  Black toner ',
          vendor: ' Acme ',
          inputVat: 92.5,
          whtAmount: 10,
          role: Expense.roleManager,
          now: DateTime(2026, 11, 22, 10),
        ),
        isNull);

    await Hive.close();
    FinanceBoxes.registerAdapters();
    await FinanceBoxes.openAll();

    final e = repo.box!.values.single;
    expect(e.date, DateTime(2026, 11, 20)); // date only
    expect(e.amount, 1234.57); // rounded to 2 places
    expect(e.categoryType, 'direct'); // copied from the category
    expect(e.paidFrom, 'Bank transfer');
    expect(e.description, 'Black toner');
    expect(e.vendor, 'Acme');
    expect(e.inputVat, 92.5);
    expect(e.whtAmount, 10);
    expect(e.createdByRole, 'manager');
    expect(e.isVoided, isFalse);
  });

  test('required fields and rules are enforced', () async {
    expect(await add(amount: 0), isNotNull);
    expect(await add(amount: -5), isNotNull);
    expect(await add(amount: 0.001), isNotNull); // rounds to zero
    expect(await add(amount: double.nan), isNotNull);
    expect(await add(cat: 'nope'), isNotNull);
    expect(await add(paidFrom: '  '), isNotNull);
    expect(await add(date: DateTime(2026, 11, 23)), isNotNull); // future
    expect(await add(vat: -1), isNotNull);

    final cat = FinanceRepository.instance.expenseCategoryBox!.get('seed_op_rent')!;
    await FinanceRepository.instance.setExpenseCategoryArchived(cat, true);
    expect(await add(), isNotNull); // archived category refused

    expect(repo.box!.isEmpty, isTrue);
  });

  test('cashier rules: no Not in P&L, and the manager switch is honoured', () async {
    expect(await add(cat: 'seed_np_drawings', role: Expense.roleCashier), isNotNull);
    expect(await add(cat: 'seed_np_drawings', role: Expense.roleManager), isNull);
    expect(await add(role: Expense.roleCashier), isNull);

    final s = FinanceRepository.instance.settings;
    s.allowCashierExpenses = false;
    await FinanceRepository.instance.saveSettings(s);
    expect(await add(role: Expense.roleCashier), isNotNull);
    expect(await add(role: Expense.roleManager), isNull); // manager unaffected
  });

  test('void needs a reason, keeps the record, and cannot repeat', () async {
    await add(amount: 500);
    final e = repo.box!.values.single;

    expect(await repo.voidExpense(e, '   '), isNotNull);
    expect(e.isVoided, isFalse);

    final at = DateTime(2026, 11, 23, 9);
    expect(await repo.voidExpense(e, 'Entered twice', now: at), isNull);
    expect(e.isVoided, isTrue);
    expect(e.voidReason, 'Entered twice');
    expect(e.voidedBy, 'manager');
    expect(e.voidedAt, at);
    expect(e.amount, 500); // amount untouched
    expect(repo.box!.length, 1); // nothing deleted

    expect(await repo.voidExpense(e, 'Again'), isNotNull);
    expect(computeTotals(repo.box!.values).count, 0);
  });

  test('totals separate Not in P&L and ignore voided entries', () async {
    await add(cat: 'seed_direct_paper', amount: 100.10);
    await add(cat: 'seed_direct_ink', amount: 200.20);
    await add(cat: 'seed_op_rent', amount: 1000);
    await add(cat: 'seed_np_drawings', amount: 5000);
    await add(cat: 'seed_np_tax', amount: 250.50);
    await add(cat: 'seed_op_misc', amount: 999);
    final misc = repo.box!.values.firstWhere((e) => e.amount == 999);
    await repo.voidExpense(misc, 'Mistake');

    final t = computeTotals(repo.box!.values);
    expect(t.directMinor, 30030); // 100.10 + 200.20 with no float drift
    expect(t.operatingMinor, 100000);
    expect(t.totalExpensesMinor, 130030);
    expect(t.notInPnlMinor, 525050);
    expect(t.totalExpenses, 1300.30);
    expect(t.count, 5);
  });

  test('monthly totals cross a year boundary, newest first', () {
    Expense mk(String id, DateTime d, double a, String type) => Expense(
        id: id,
        date: d,
        createdAt: d,
        amount: a,
        categoryId: 'x',
        categoryType: type,
        paidFrom: 'Cash',
        createdByRole: 'manager');
    final months = totalsByMonth([
      mk('1', DateTime(2026, 12, 31), 10, 'operating'),
      mk('2', DateTime(2027, 1, 1), 20, 'direct'),
      mk('3', DateTime(2027, 1, 15), 5, 'non_pnl'),
    ]);
    expect(months.map((m) => m.key), [DateTime(2027, 1), DateTime(2026, 12)]);
    expect(months.first.value.totalExpensesMinor, 2000);
    expect(months.first.value.notInPnlMinor, 500);
    expect(months.last.value.totalExpensesMinor, 1000);
  });

  test('query filters are inclusive and filter by category', () async {
    await add(date: DateTime(2026, 11, 1), now: DateTime(2026, 11, 1, 8));
    await add(date: DateTime(2026, 11, 15), now: DateTime(2026, 11, 15, 8), cat: 'seed_direct_ink');
    await add(date: DateTime(2026, 11, 22), now: DateTime(2026, 11, 22, 8));

    expect(repo.query().length, 3);
    expect(repo.query(from: DateTime(2026, 11, 1), to: DateTime(2026, 11, 15)).length, 2);
    expect(repo.query(from: DateTime(2026, 11, 2), to: DateTime(2026, 11, 14)).length, 0);
    expect(repo.query(categoryId: 'seed_direct_ink').length, 1);
    expect(repo.query().first.date, DateTime(2026, 11, 22)); // newest first
  });

  test('a cashier sees only expenses a cashier entered today', () async {
    final morning = DateTime(2026, 11, 22, 9);
    await add(role: Expense.roleCashier, now: morning, amount: 10);
    await add(role: Expense.roleCashier, now: morning, amount: 20); // same instant, own id
    await add(role: Expense.roleManager, now: morning, amount: 30);
    await add(role: Expense.roleCashier, now: DateTime(2026, 11, 21, 9), amount: 40);

    expect(repo.box!.length, 4); // no id collision
    final seen = repo.enteredTodayByCashier(now: DateTime(2026, 11, 22, 18));
    expect(seen.map((e) => e.amount).toSet(), {10.0, 20.0});
    expect(repo.enteredTodayByCashier(now: DateTime(2026, 11, 23, 8)), isEmpty);
  });

  test('the old expenses_box is never touched', () async {
    expect(Hive.isBoxOpen('expenses_box'), isFalse);
    expect(FinanceBoxes.expensesBox, isNot('expenses_box'));
  });
}
