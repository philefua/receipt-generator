import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'finance_repository.dart';
import 'models/asset.dart';
import 'models/asset_category.dart';
import 'models/expense_category.dart';
import 'models/finance_settings.dart';
import 'models/loan.dart';
import 'models/loan_transaction.dart';
import 'models/receipt_link.dart';
import 'models/stock_count.dart';

/// The one place that knows every finance box and Hive typeId.
///
/// Backup and restore (phase 11) must use [allBoxNames] so a box can never
/// be forgotten. Opening is fault tolerant: a box that fails to open is
/// logged and skipped, and the app still launches.
///
/// Hive typeIds in use across the whole app:
///   0 BusinessSettings, 1 ProductPreset, 2 ReceiptItem, 3 Receipt,
///   4 LicenseState, 5 Expense (old, daily-expenses branch only).
///   6 FinanceSettings, 7 ExpenseCategory, 8 AssetCategory, 9 ReceiptLink,
///   10 StockCount, 11 Asset, 12 Loan, 13 LoanTransaction.
///   14 is reserved for the reworked Expense (phase 4).
class FinanceBoxes {
  FinanceBoxes._();

  static const String settingsBox = 'finance_settings_box';
  static const String expenseCategoriesBox = 'expense_categories_box';
  static const String assetCategoriesBox = 'asset_categories_box';
  static const String receiptLinksBox = 'receipt_links_box';
  static const String stockCountsBox = 'stock_counts_box';
  static const String assetsBox = 'assets_box';
  static const String loansBox = 'loans_box';
  static const String loanTransactionsBox = 'loan_transactions_box';

  /// Every finance box, for backup and restore. Add new boxes here.
  static const List<String> allBoxNames = [
    settingsBox,
    expenseCategoriesBox,
    assetCategoriesBox,
    receiptLinksBox,
    stockCountsBox,
    assetsBox,
    loansBox,
    loanTransactionsBox,
  ];

  /// Names of boxes that failed to open on this launch, with the reason.
  static final Map<String, String> failures = <String, String>{};

  static void registerAdapters() {
    _register<FinanceSettings>(6, FinanceSettingsAdapter());
    _register<ExpenseCategory>(7, ExpenseCategoryAdapter());
    _register<AssetCategory>(8, AssetCategoryAdapter());
    _register<ReceiptLink>(9, ReceiptLinkAdapter());
    _register<StockCount>(10, StockCountAdapter());
    _register<Asset>(11, AssetAdapter());
    _register<Loan>(12, LoanAdapter());
    _register<LoanTransaction>(13, LoanTransactionAdapter());
  }

  static void _register<T>(int typeId, TypeAdapter<T> adapter) {
    try {
      if (!Hive.isAdapterRegistered(typeId)) {
        Hive.registerAdapter<T>(adapter);
      }
    } catch (e) {
      failures['adapter_$typeId'] = e.toString();
      debugPrint('Finance adapter $typeId failed to register: $e');
    }
  }

  /// Opens every finance box, then seeds defaults. Never throws.
  static Future<void> openAll() async {
    failures.clear();
    await _open<FinanceSettings>(settingsBox);
    await _open<ExpenseCategory>(expenseCategoriesBox);
    await _open<AssetCategory>(assetCategoriesBox);
    await _open<ReceiptLink>(receiptLinksBox);
    await _open<StockCount>(stockCountsBox);
    await _open<Asset>(assetsBox);
    await _open<Loan>(loansBox);
    await _open<LoanTransaction>(loanTransactionsBox);
    try {
      await FinanceRepository.instance.initialize();
    } catch (e) {
      failures['seed'] = e.toString();
      debugPrint('Finance defaults could not be created: $e');
    }
  }

  static Future<void> _open<T>(String name) async {
    try {
      if (!Hive.isBoxOpen(name)) {
        await Hive.openBox<T>(name);
      }
    } catch (e) {
      failures[name] = e.toString();
      debugPrint('Finance box $name failed to open: $e');
    }
  }
}
