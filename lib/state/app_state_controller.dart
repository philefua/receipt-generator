import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/business_settings.dart';
import '../models/cart_item.dart';
import '../models/expense.dart';
import '../models/expense_options.dart';
import '../models/product_preset.dart';
import '../models/receipt.dart';
import '../utils/discount_code_util.dart';

class AppStateController extends ChangeNotifier {
  static const String _settingsBoxName = 'settings_box';
  static const String _productsBoxName = 'products_box';
  static const String _receiptsBoxName = 'receipts_box';
  static const String _expensesBoxName = 'expenses_box';
  static const String _settingsKey = 'business_settings';

  late final Box<BusinessSettings> _settingsBox;
  late final Box<ProductPreset> _productsBox;
  late final Box<Receipt> _receiptsBox;
  late final Box<Expense> _expensesBox;

  final List<CartItem> _cart = [];
  double _discountPercent = 0;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    _settingsBox = await Hive.openBox<BusinessSettings>(_settingsBoxName);
    _productsBox = await Hive.openBox<ProductPreset>(_productsBoxName);
    _receiptsBox = await Hive.openBox<Receipt>(_receiptsBoxName);
    _expensesBox = await Hive.openBox<Expense>(_expensesBoxName);

    if (!_settingsBox.containsKey(_settingsKey)) {
      await _settingsBox.put(
        _settingsKey,
        BusinessSettings(managerPasswordHash: _hashPassword('admin123')),
      );
    }

    _initialized = true;
    notifyListeners();
  }

  BusinessSettings get settings => _settingsBox.get(_settingsKey)!;

  static String _hashPassword(String raw) =>
      sha256.convert(utf8.encode(raw)).toString();

  bool verifyManagerPassword(String attempt) =>
      settings.managerPasswordHash == _hashPassword(attempt);

  Future<void> updateManagerPassword(String newPassword) async {
    settings.managerPasswordHash = _hashPassword(newPassword);
    await settings.save();
    notifyListeners();
  }

  Future<void> updateBusinessDetails({
    String? businessName,
    String? address,
    String? phone,
    String? logoPath,
    String? currencySymbol,
    String? whatsapp,
    String? website,
    String? instagram,
    String? facebook,
    String? footnote,
  }) async {
    final s = settings;
    if (businessName != null) s.businessName = businessName;
    if (address != null) s.address = address;
    if (phone != null) s.phone = phone;
    if (logoPath != null) s.logoPath = logoPath;
    if (currencySymbol != null) s.currencySymbol = currencySymbol;
    if (whatsapp != null) s.whatsapp = whatsapp;
    if (website != null) s.website = website;
    if (instagram != null) s.instagram = instagram;
    if (facebook != null) s.facebook = facebook;
    if (footnote != null) s.footnote = footnote;
    await s.save();
    notifyListeners();
  }

  Future<void> updateGoogleSheetId(String sheetIdOrUrl) async {
    settings.googleSheetId = sheetIdOrUrl.trim();
    await settings.save();
    notifyListeners();
  }

  /// Records that a Drive backup just completed successfully, used by the
  /// automatic daily check to know when it last ran.
  Future<void> recordBackupCompleted() async {
    settings.lastBackupAt = DateTime.now();
    await settings.save();
    notifyListeners();
  }

  /// Records that a Sheets product sync just completed successfully.
  Future<void> recordSyncCompleted() async {
    settings.lastSyncAt = DateTime.now();
    await settings.save();
    notifyListeners();
  }

  /// True if 24+ hours have passed since the last successful backup, or
  /// if a backup has never run at all.
  bool get isBackupDue {
    final last = settings.lastBackupAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= const Duration(hours: 24);
  }

  /// True if 24+ hours have passed since the last successful sync, or if
  /// a sync has never run at all. Only meaningful once a Google Sheet has
  /// actually been configured.
  bool get isSyncDue {
    if (settings.googleSheetId.trim().isEmpty) return false;
    final last = settings.lastSyncAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= const Duration(hours: 24);
  }

 List<ProductPreset> get productPresets {
    final active = _productsBox.values.where((p) => p.isActive).toList();
    active.sort(
      (a, b) => a.name.trim().toLowerCase().compareTo(b.name.trim().toLowerCase()),
    );
    return List.unmodifiable(active);
  }

  Future<void> addProductPreset({
    required String name,
    required double price,
    String? category,
  }) async {
    final preset = ProductPreset(
      id: const Uuid().v4(),
      name: name,
      price: price,
      category: category,
    );
    await _productsBox.put(preset.id, preset);
    notifyListeners();
  }

  Future<void> updateProductPreset(
    String id, {
    String? name,
    double? price,
    String? category,
  }) async {
    final preset = _productsBox.get(id);
    if (preset == null) return;
    if (name != null) preset.name = name;
    if (price != null) preset.price = price;
    if (category != null) preset.category = category;
    await preset.save();
    notifyListeners();
  }

  Future<void> deactivateProductPreset(String id) async {
    final preset = _productsBox.get(id);
    if (preset == null) return;
    preset.isActive = false;
    await preset.save();
    notifyListeners();
  }

  /// Replaces all active preset products with [products] — used by the
  /// Google Sheets sync to make local presets match the remote sheet
  /// exactly. Existing products not present in the new list are
  /// deactivated (soft-deleted, consistent with the rest of the app's
  /// deletion behavior), rather than hard-deleted.
  Future<void> replaceProductPresetsFromSync(
    List<MapEntry<String, double>> products,
  ) async {
    final existingByName = <String, ProductPreset>{
      for (final p in _productsBox.values.where((p) => p.isActive))
        p.name.trim().toLowerCase(): p,
    };

    final incomingNames = <String>{};

    for (final entry in products) {
      final name = entry.key.trim();
      final price = entry.value;
      final key = name.toLowerCase();
      incomingNames.add(key);

      final existing = existingByName[key];
      if (existing != null) {
        existing.price = price;
        await existing.save();
      } else {
        final preset = ProductPreset(
          id: const Uuid().v4(),
          name: name,
          price: price,
        );
        await _productsBox.put(preset.id, preset);
      }
    }

    for (final entry in existingByName.entries) {
      if (!incomingNames.contains(entry.key)) {
        entry.value.isActive = false;
        await entry.value.save();
      }
    }

    notifyListeners();
  }

  List<CartItem> get cart => List.unmodifiable(_cart);

  double get discountPercent => _discountPercent;

  void addToCart(ProductPreset product, {int quantity = 1}) {
    final existingIndex = _cart.indexWhere((c) => c.presetId == product.id);
    if (existingIndex != -1) {
      _cart[existingIndex].quantity += quantity;
    } else {
      _cart.add(CartItem(
        id: const Uuid().v4(),
        presetId: product.id,
        name: product.name,
        unitPrice: product.price,
        quantity: quantity,
      ));
    }
    notifyListeners();
  }

  void addManualItemToCart({
    required String name,
    required double unitPrice,
    int quantity = 1,
  }) {
    if (name.trim().isEmpty || unitPrice < 0 || quantity <= 0) {
      throw ArgumentError('Invalid manual item details.');
    }
    _cart.add(CartItem(
      id: const Uuid().v4(),
      presetId: null,
      name: name.trim(),
      unitPrice: unitPrice,
      quantity: quantity,
    ));
    notifyListeners();
  }

  void updateCartQuantity(String cartItemId, int quantity) {
    if (quantity <= 0) {
      removeFromCart(cartItemId);
      return;
    }
    final index = _cart.indexWhere((c) => c.id == cartItemId);
    if (index != -1) {
      _cart[index].quantity = quantity;
      notifyListeners();
    }
  }

  void removeFromCart(String cartItemId) {
    _cart.removeWhere((c) => c.id == cartItemId);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _discountPercent = 0;
    notifyListeners();
  }

  void setDiscountPercent(double percent) {
    if (percent < 0 || percent > 100) {
      throw ArgumentError('Discount percent must be between 0 and 100.');
    }
    _discountPercent = percent;
    notifyListeners();
  }

  double get subtotal => _cart.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get discountAmount =>
      double.parse((subtotal * (_discountPercent / 100)).toStringAsFixed(2));

  double get totalPayable =>
      double.parse((subtotal - discountAmount).toStringAsFixed(2));

  int _nextDailyCounter(DateTime now) {
    final todayKey = now.year * 10000 + now.month * 100 + now.day;
    final s = settings;
    if (s.lastReceiptCounterDate != todayKey) {
      s.lastReceiptCounterDate = todayKey;
      s.dailyReceiptCounter = 0;
    }
    s.dailyReceiptCounter += 1;
    return s.dailyReceiptCounter;
  }

  Future<Receipt> finalizeAndSaveReceipt({
    required String cashierName,
    required String customerName,
    required String customerWhatsapp,
    required String paymentMethod,
    String couponReference = '',
    double? depositPaid,
  }) async {
    if (_cart.isEmpty) {
      throw StateError('Cannot finalize an empty cart.');
    }
    if (customerName.trim().isEmpty || customerWhatsapp.trim().isEmpty) {
      throw StateError('Customer name and WhatsApp number are required.');
    }

    final now = DateTime.now();
    final counter = _nextDailyCounter(now);
    final code = DiscountCodeUtil.generateReceiptCode(
      date: now,
      dailyOrderNumber: counter,
    );

    final frozenItems = _cart
        .map((c) => ReceiptItem(
              productId: c.presetId ?? 'manual',
              name: c.name,
              unitPrice: c.unitPrice,
              quantity: c.quantity,
              lineTotal: double.parse(c.lineTotal.toStringAsFixed(2)),
            ))
        .toList(growable: false);

    final resolvedTotalPayable = totalPayable;
    final resolvedDepositPaid = (depositPaid == null || depositPaid <= 0)
        ? resolvedTotalPayable
        : (depositPaid > resolvedTotalPayable
            ? resolvedTotalPayable
            : depositPaid);
    final resolvedBalanceOwed = double.parse(
      (resolvedTotalPayable - resolvedDepositPaid).toStringAsFixed(2),
    );

    final receipt = Receipt(
      receiptCode: code,
      issuedAt: now,
      items: frozenItems,
      subtotal: subtotal,
      discountPercent: _discountPercent,
      discountAmount: discountAmount,
      totalPayable: resolvedTotalPayable,
      cashierName: cashierName,
      isLocked: true,
      customerName: customerName.trim(),
      customerWhatsapp: customerWhatsapp.trim(),
      paymentMethod: paymentMethod,
      couponReference: couponReference.trim(),
      depositPaid: resolvedDepositPaid,
      balanceOwed: resolvedBalanceOwed < 0 ? 0 : resolvedBalanceOwed,
    );

    await _receiptsBox.add(receipt);
    await settings.save();

    clearCart();
    return receipt;
  }

  List<Receipt> get receiptHistory {
    final list = _receiptsBox.values.toList();
    list.sort((a, b) => b.issuedAt.compareTo(a.issuedAt));
    return List.unmodifiable(list);
  }

  // ---------------------------------------------------------------------
  // Daily expense record
  //
  // Each Expense maps onto one row of tab 3_Expense_Ledger in the
  // Printiverse financial workbook. Expenses are never deleted: a mistaken
  // entry is voided (manager password required), which removes it from
  // totals and from the export while keeping the record.
  // ---------------------------------------------------------------------

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));

  static int _newestFirst(Expense a, Expense b) {
    final byDate = b.date.compareTo(a.date);
    return byDate != 0 ? byDate : b.voucher.compareTo(a.voucher);
  }

  static int _oldestFirst(Expense a, Expense b) {
    final byDate = a.date.compareTo(b.date);
    return byDate != 0 ? byDate : a.voucher.compareTo(b.voucher);
  }

  /// Every expense ever recorded, including voided ones, newest first.
  List<Expense> get allExpenses {
    final list = _expensesBox.values.toList();
    list.sort(_newestFirst);
    return List.unmodifiable(list);
  }

  /// Expenses dated [day], including voided ones (shown struck through),
  /// newest first.
  List<Expense> expensesForDay(DateTime day) {
    final list =
        _expensesBox.values.where((e) => _sameDay(e.date, day)).toList();
    list.sort(_newestFirst);
    return List.unmodifiable(list);
  }

  /// Non-voided expenses, oldest first. This is exactly what the expense
  /// export writes into the workbook's expense ledger.
  List<Expense> get exportableExpenses {
    final list = _expensesBox.values.where((e) => !e.isVoided).toList();
    list.sort(_oldestFirst);
    return List.unmodifiable(list);
  }

  /// Cash paid out on [day] (Net + Input VAT - WHT), voided entries excluded.
  double totalCashPaidForDay(DateTime day) {
    final total = _expensesBox.values
        .where((e) => !e.isVoided && _sameDay(e.date, day))
        .fold<double>(0, (sum, e) => sum + e.totalCashPaid);
    return _round2(total);
  }

  /// Money actually collected from receipts issued on [day] (deposits paid,
  /// so part-payments are not overstated).
  double salesCollectedForDay(DateTime day) {
    final total = _receiptsBox.values
        .where((r) => _sameDay(r.issuedAt, day))
        .fold<double>(0, (sum, r) => sum + r.depositPaid);
    return _round2(total);
  }

  static final RegExp _voucherPattern = RegExp(r'^EXP-(\d+)$');

  /// The next voucher number, EXP-0001 onwards. Voided entries keep their
  /// number, so numbers are never reused.
  String nextVoucher() {
    var highest = 0;
    for (final e in _expensesBox.values) {
      final match = _voucherPattern.firstMatch(e.voucher);
      if (match == null) continue;
      final n = int.tryParse(match.group(1)!) ?? 0;
      if (n > highest) highest = n;
    }
    return 'EXP-${(highest + 1).toString().padLeft(4, '0')}';
  }

  /// Returns a plain-English problem with the entry, or null if it is valid.
  /// Used by the expense page to show errors, and again by [addExpense] as
  /// a safety net, so the rules live in one place.
  String? validateExpense({
    required DateTime date,
    required String vendor,
    required String description,
    required String costType,
    required String category,
    required double? netAmount,
    required double inputVat,
    required double whtDeducted,
    required String paymentAccount,
    required String receiptStatus,
    required String notes,
  }) {
    if (_dateOnly(date).isAfter(_dateOnly(DateTime.now()))) {
      return 'The date cannot be in the future.';
    }
    if (vendor.trim().isEmpty) return 'Enter the vendor or payee.';
    if (description.trim().isEmpty) {
      return 'Describe what was paid for, with quantity.';
    }
    if (!ExpenseOptions.costTypes.contains(costType)) {
      return 'Choose a cost type.';
    }
    if (!ExpenseOptions.isValidPair(costType, category)) {
      return 'Choose a category that belongs to $costType.';
    }
    if (netAmount == null || netAmount <= 0) {
      return 'Enter an amount greater than zero.';
    }
    if (inputVat < 0 || whtDeducted < 0) {
      return 'VAT and WHT cannot be negative.';
    }
    if (!ExpenseOptions.allowsVatAndWht(costType) &&
        (inputVat != 0 || whtDeducted != 0)) {
      return '$costType entries cannot carry Input VAT or WHT.';
    }
    if (whtDeducted > netAmount + inputVat) {
      return 'WHT cannot be more than the net amount plus VAT.';
    }
    if (!ExpenseOptions.paymentAccounts.contains(paymentAccount)) {
      return 'Choose a payment account.';
    }
    if (!ExpenseOptions.receiptStatuses.contains(receiptStatus)) {
      return 'Choose a receipt status.';
    }
    if (ExpenseOptions.requiresAssetTag(costType) && notes.trim().isEmpty) {
      return 'CapEx needs a serial number or asset tag in Notes.';
    }
    return null;
  }

  /// Saves a new expense and assigns its voucher number. Throws an
  /// [ArgumentError] carrying the [validateExpense] message if the entry
  /// breaks a rule.
  Future<Expense> addExpense({
    required DateTime date,
    required String vendor,
    required String description,
    required String costType,
    required String category,
    required double netAmount,
    double inputVat = 0,
    double whtDeducted = 0,
    required String paymentAccount,
    required String receiptStatus,
    String recordedBy = '',
    String notes = '',
  }) async {
    final problem = validateExpense(
      date: date,
      vendor: vendor,
      description: description,
      costType: costType,
      category: category,
      netAmount: netAmount,
      inputVat: inputVat,
      whtDeducted: whtDeducted,
      paymentAccount: paymentAccount,
      receiptStatus: receiptStatus,
      notes: notes,
    );
    if (problem != null) throw ArgumentError(problem);

    final expense = Expense(
      id: const Uuid().v4(),
      date: _dateOnly(date),
      voucher: nextVoucher(),
      vendor: vendor.trim(),
      description: description.trim(),
      costType: costType,
      category: category,
      netAmount: _round2(netAmount),
      inputVat: _round2(inputVat),
      whtDeducted: _round2(whtDeducted),
      paymentAccount: paymentAccount,
      receiptStatus: receiptStatus,
      recordedBy: recordedBy.trim(),
      notes: notes.trim(),
      recordedAt: DateTime.now(),
    );
    await _expensesBox.put(expense.id, expense);
    notifyListeners();
    return expense;
  }

  /// Voids an expense (soft delete). Needs the manager password; returns
  /// false, changing nothing, if the password is wrong or the entry is gone.
  Future<bool> voidExpense(
    String id, {
    required String managerPassword,
  }) async {
    if (!verifyManagerPassword(managerPassword)) return false;
    final expense = _expensesBox.get(id);
    if (expense == null) return false;
    if (expense.isVoided) return true;
    expense.isVoided = true;
    await expense.save();
    notifyListeners();
    return true;
  }

  Receipt? findReceiptByCode(String code) {
    try {
      return _receiptsBox.values.firstWhere((r) => r.receiptCode == code);
    } catch (_) {
      return null;
    }
  }
}