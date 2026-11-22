import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:receipt_generator/features/finance/finance_boxes.dart';
import 'package:receipt_generator/features/finance/finance_repository.dart';
import 'package:receipt_generator/features/finance/models/asset.dart';
import 'package:receipt_generator/features/finance/models/asset_category.dart';
import 'package:receipt_generator/features/finance/models/expense_category.dart';
import 'package:receipt_generator/features/finance/models/finance_settings.dart';
import 'package:receipt_generator/features/finance/models/loan.dart';
import 'package:receipt_generator/features/finance/models/loan_transaction.dart';
import 'package:receipt_generator/features/finance/models/receipt_link.dart';
import 'package:receipt_generator/features/finance/models/stock_count.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('finance_test_');
    Hive.init(dir.path);
    FinanceBoxes.registerAdapters();
  });

  tearDown(() async {
    await Hive.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('typeIds do not collide with the existing app (0 to 5)', () {
    const ids = [6, 7, 8, 9, 10, 11, 12, 13];
    expect(ids.toSet().length, ids.length);
    expect(ids.every((i) => i >= 6), isTrue);
    for (final i in ids) {
      expect(Hive.isAdapterRegistered(i), isTrue, reason: 'typeId $i');
    }
  });

  test('seeding creates the generic categories once and is idempotent', () async {
    await FinanceBoxes.openAll();
    final repo = FinanceRepository.instance;
    expect(repo.isReady, isTrue);
    expect(FinanceBoxes.failures, isEmpty);

    expect(repo.expenseCategories(ExpenseCategory.groupDirect).length, 6);
    expect(repo.expenseCategories(ExpenseCategory.groupOperating).length, 10);
    final notInPnl = repo.expenseCategories(ExpenseCategory.groupNotInPnl);
    expect(notInPnl.map((c) => c.name),
        containsAll(['Owner drawings', 'Tax remittances']));
    expect(repo.assetCategoryBox!.length, 6);

    // Manager renames and archives, then initialize runs again (next launch).
    final toner = repo.expenseCategoryBox!.get('seed_direct_toner')!;
    expect(await repo.renameExpenseCategory(toner, 'Toner and ink'), isNull);
    await repo.setExpenseCategoryArchived(
        repo.expenseCategoryBox!.get('seed_direct_ink')!, true);
    await repo.initialize();

    expect(repo.expenseCategoryBox!.length, 18);
    expect(repo.expenseCategoryBox!.get('seed_direct_toner')!.name, 'Toner and ink');
    expect(repo.expenseCategoryBox!.get('seed_direct_ink')!.archived, isTrue);
  });

  test('settings default and paid-from list survive a close and reopen', () async {
    await FinanceBoxes.openAll();
    final repo = FinanceRepository.instance;
    final s = repo.settings;
    expect(s.allowCashierExpenses, isTrue);
    expect(s.financialYearStartMonth, 1);
    expect(s.paidFromOptions, ['Cash', 'Bank transfer', 'POS', 'Mobile money']);

    s.vatEnabled = true;
    s.vatRatePercent = 7.5;
    s.openingCashDate = DateTime(2026, 1, 1);
    await repo.saveSettings(s);
    expect(await repo.addPaidFrom('Cheque'), isNull);
    expect(await repo.addPaidFrom('cash'), isNotNull); // duplicate, case-insensitive

    await Hive.close();
    FinanceBoxes.registerAdapters();
    await FinanceBoxes.openAll();

    final again = FinanceRepository.instance.settings;
    expect(again.vatEnabled, isTrue);
    expect(again.vatRatePercent, 7.5);
    expect(again.openingCashDate, DateTime(2026, 1, 1));
    expect(again.paidFromOptions.last, 'Cheque');
  });

  test('category names must be unique inside a group', () async {
    await FinanceBoxes.openAll();
    final repo = FinanceRepository.instance;
    expect(await repo.addExpenseCategory('rent', ExpenseCategory.groupOperating),
        isNotNull);
    expect(await repo.addExpenseCategory('Rent', ExpenseCategory.groupDirect),
        isNull);
    expect(await repo.addExpenseCategory('  ', ExpenseCategory.groupDirect),
        isNotNull);
  });

  test('every model round-trips through its adapter', () async {
    final now = DateTime(2026, 11, 22, 10, 30);
    final assets = await Hive.openBox<Asset>('t_assets');
    final loans = await Hive.openBox<Loan>('t_loans');
    final txs = await Hive.openBox<LoanTransaction>('t_txs');
    final links = await Hive.openBox<ReceiptLink>('t_links');
    final stock = await Hive.openBox<StockCount>('t_stock');
    final cats = await Hive.openBox<AssetCategory>('t_acats');
    final sets = await Hive.openBox<FinanceSettings>('t_sets');

    await assets.put(
        'a',
        Asset(
          id: 'a',
          name: 'Printer',
          categoryId: 'seed_asset_machines',
          purchaseDate: now,
          cost: 250000.5,
          paymentMethod: 'Cash',
          usefulLifeMonths: 60,
          createdAt: now,
        ));
    await loans.put(
        'l',
        Loan(
          id: 'l',
          lenderName: 'Bank',
          lenderType: 'bank',
          dateReceived: now,
          principal: 1000000,
          receivedInto: 'Bank transfer',
          createdAt: now,
        ));
    await txs.put(
        't',
        LoanTransaction(
          id: 't',
          loanId: 'l',
          date: now,
          principalAmount: 50000,
          interestAmount: 4000,
          paymentMethod: 'Bank transfer',
          createdAt: now,
        ));
    await links.put(
        'k',
        ReceiptLink(
          id: 'k',
          kind: ReceiptLink.kindWriteoff,
          receiptCode: 'ZKq05',
          originalReceiptCode: 'ZKq05',
          amount: 500,
          reason: 'Customer short-paid',
          createdAt: now,
        ));
    await stock.put('s', StockCount(id: 's', date: now, value: 12000, createdAt: now));
    await cats.put(
        'c',
        AssetCategory(
            id: 'c', name: 'Vehicles', defaultUsefulLifeMonths: 48, createdAt: now));
    await sets.put('x', FinanceSettings(paidFromOptions: ['Cash']));

    await Hive.close();
    FinanceBoxes.registerAdapters();
    final a = (await Hive.openBox<Asset>('t_assets')).get('a')!;
    expect(a.cost, 250000.5);
    expect(a.method, Asset.methodStraightLine);
    expect(a.status, Asset.statusActive);
    expect(a.vendor, isNull);
    expect(a.isOpeningBalance, isFalse);
    expect((await Hive.openBox<Loan>('t_loans')).get('l')!.principal, 1000000);
    final t = (await Hive.openBox<LoanTransaction>('t_txs')).get('t')!;
    expect(t.principalAmount, 50000);
    expect(t.interestAmount, 4000);
    expect((await Hive.openBox<ReceiptLink>('t_links')).get('k')!.kind, 'writeoff');
    expect((await Hive.openBox<StockCount>('t_stock')).get('s')!.value, 12000);
    expect((await Hive.openBox<AssetCategory>('t_acats')).get('c')!.defaultUsefulLifeMonths, 48);
    expect((await Hive.openBox<FinanceSettings>('t_sets')).get('x')!.paidFromOptions, ['Cash']);
  });
}
