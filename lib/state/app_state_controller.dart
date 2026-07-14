import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/business_settings.dart';
import '../models/cart_item.dart';
import '../models/product_preset.dart';
import '../models/receipt.dart';
import '../utils/discount_code_util.dart';

class AppStateController extends ChangeNotifier {
  static const String _settingsBoxName = 'settings_box';
  static const String _productsBoxName = 'products_box';
  static const String _receiptsBoxName = 'receipts_box';
  static const String _settingsKey = 'business_settings';

  late final Box<BusinessSettings> _settingsBox;
  late final Box<ProductPreset> _productsBox;
  late final Box<Receipt> _receiptsBox;

  final List<CartItem> _cart = [];
  double _discountPercent = 0;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    _settingsBox = await Hive.openBox<BusinessSettings>(_settingsBoxName);
    _productsBox = await Hive.openBox<ProductPreset>(_productsBoxName);
    _receiptsBox = await Hive.openBox<Receipt>(_receiptsBoxName);

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

  List<ProductPreset> get productPresets =>
      List.unmodifiable(_productsBox.values.where((p) => p.isActive));

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

    final total = totalPayable;
    final resolvedDeposit = (depositPaid == null || depositPaid <= 0 || depositPaid >= total)
        ? total
        : depositPaid;
    final resolvedBalance =
        double.parse((total - resolvedDeposit).toStringAsFixed(2));

    final receipt = Receipt(
      receiptCode: code,
      issuedAt: now,
      items: frozenItems,
      subtotal: subtotal,
      discountPercent: _discountPercent,
      discountAmount: discountAmount,
      totalPayable: total,
      cashierName: cashierName,
      isLocked: true,
      customerName: customerName.trim(),
      customerWhatsapp: customerWhatsapp.trim(),
      paymentMethod: paymentMethod,
      couponReference: couponReference.trim(),
      depositPaid: resolvedDeposit,
      balanceOwed: resolvedBalance < 0 ? 0 : resolvedBalance,
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

  Receipt? findReceiptByCode(String code) {
    try {
      return _receiptsBox.values.firstWhere((r) => r.receiptCode == code);
    } catch (_) {
      return null;
    }
  }
}