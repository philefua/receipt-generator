import 'package:flutter/material.dart';
import '../models/business_settings.dart';
import '../models/product_preset.dart';
import '../models/receipt.dart';
import '../models/cart_item.dart';
import '../utils/discounts_code_util.dart';

class AppStateController extends ChangeNotifier {
  final List<CartItem> _cart = [];
  final List<ProductPreset> _presets = [];
  final List<Receipt> _history = [];
  double _discountPercent = 0.0;
  
  // Guarantee settings are initialized so the app doesn't crash on null properties
  BusinessSettings _settings = BusinessSettings();

  List<CartItem> get cart => List.unmodifiable(_cart);
  List<ProductPreset> get productPresets => _presets.where((p) => p.isActive).toList();
  List<Receipt> get receiptHistory => List.unmodifiable(_history);
  double get discountPercent => _discountPercent;
  BusinessSettings get settings => _settings;

  double get subtotal => _cart.fold(0.0, (sum, item) => sum + item.lineTotal);
  double get discountAmount => double.parse((subtotal * (_discountPercent / 100)).toStringAsFixed(2));
  double get totalPayable => subtotal - discountAmount;
  double get amountPayable => totalPayable;

  // Called by main.dart on startup
  Future<void> init() async {
    // Add default sample items if presets are empty
    if (_presets.isEmpty) {
      _presets.add(ProductPreset(id: "1", description: "Standard Banner Print", unitPrice: 5000.0));
      _presets.add(ProductPreset(id: "2", description: "Custom Apparel Branding", unitPrice: 3500.0));
    }
    notifyListeners();
  }

  bool verifyManagerPassword(String enteredPassword) {
    return _settings.managerPassword == enteredPassword;
  }

  Future<void> updateBusinessDetails({
    required String businessName,
    required String address,
    required String whatsapp,
    required String website,
    required String instagram,
    required String facebook,
    required String footnote,
  }) async {
    _settings.businessName = businessName;
    _settings.address = address;
    _settings.whatsapp = whatsapp;
    _settings.website = website;
    _settings.instagram = instagram;
    _settings.facebook = facebook;
    _settings.footnote = footnote;
    notifyListeners();
  }

  Future<void> addProductPreset({required String name, required double price}) async {
    _presets.add(ProductPreset(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      description: name,
      unitPrice: price,
    ));
    notifyListeners();
  }

  Future<void> updateProductPreset({required String id, required String name, required double price}) async {
    final index = _presets.indexWhere((p) => p.id == id);
    if (index >= 0) {
      _presets[index] = ProductPreset(id: id, description: name, unitPrice: price);
      notifyListeners();
    }
  }

  Future<void> deactivateProductPreset(String id) async {
    final index = _presets.indexWhere((p) => p.id == id);
    if (index >= 0) {
      _presets[index] = ProductPreset(
        id: _presets[index].id,
        description: _presets[index].description,
        unitPrice: _presets[index].unitPrice,
        isActive: false,
      );
      notifyListeners();
    }
  }

  void addToCart(ProductPreset product, {int quantity = 1}) {
    final existingIndex = _cart.indexWhere((c) => c.product.id == product.id);
    if (existingIndex >= 0) {
      _cart[existingIndex].quantity += quantity;
    } else {
      _cart.add(CartItem(product: product, quantity: quantity));
    }
    notifyListeners();
  }

  void addManualItemToCart(String description, double unitPrice, int quantity) {
    final tempProduct = ProductPreset(
      id: "manual_${DateTime.now().millisecondsSinceEpoch}",
      description: description,
      unitPrice: unitPrice,
    );
    _cart.add(CartItem(product: tempProduct, quantity: quantity));
    notifyListeners();
  }

  void updateCartQuantity(String productId, int quantity) {
    final index = _cart.indexWhere((c) => c.product.id == productId);
    if (index >= 0) {
      _cart[index].quantity = quantity;
      notifyListeners();
    }
  }

  void removeFromCart(String productId) {
    _cart.removeWhere((c) => c.product.id == productId);
    notifyListeners();
  }

  void clearCart() {
    _cart.clear();
    _discountPercent = 0.0;
    notifyListeners();
  }

  void setDiscountPercent(double percent) {
    _discountPercent = percent;
    notifyListeners();
  }

  Future<void> finalizeAndSaveReceipt({
    required String customerName,
    required String customerWhatsApp,
    required String paymentMethod,
    String cashierName = "", 
  }) async {
    if (_cart.isEmpty) return;

    final nextOrderNum = _history.length + 1;
    final receiptCode = DiscountCodeUtil.generateReceiptCode(nextOrderNum);

    final newReceipt = Receipt(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      receiptCode: receiptCode,
      timestamp: DateTime.now(),
      customerName: customerName,
      customerWhatsApp: customerWhatsApp,
      items: List.from(_cart),
      subtotal: subtotal,
      discountPercent: _discountPercent,
      discountAmount: discountAmount,
      amountPayable: totalPayable,
      paymentMethod: paymentMethod,
    );

    _history.add(newReceipt);
    clearCart();
  }
}
