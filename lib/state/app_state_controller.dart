import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/business_settings.dart';
import '../models/product_preset.dart';
import '../models/receipt.dart';
import '../models/cart_item.dart';
import '../utils/discounts_code_util.dart';

class AppStateController extends ChangeNotifier {
  final List<CartItem> _cart = [];
  double _discountPercent = 0.0;
  BusinessSettings? _settings;

  List<CartItem> get cart => List.unmodifiable(_cart);
  double get discountPercent => _discountPercent;
  BusinessSettings? get settings => _settings;

  double get subtotal => _cart.fold(0.0, (sum, item) => sum + (item.unitPrice * item.quantity));
  double get discountAmount => double.parse((subtotal * (_discountPercent / 100)).toStringAsFixed(2));
  double get amountPayable => subtotal - discountAmount;

  void setBusinessSettings(BusinessSettings newSettings) {
    _settings = newSettings;
    notifyListeners();
  }

  void addToCart(ProductPreset product, {int quantity = 1}) {
    final existingIndex = _cart.indexWhere((c) => c.presetId == product.id);
    if (existingIndex >= 0) {
      _cart[existingIndex].quantity += quantity;
    } else {
      _cart.add(CartItem(
        id: const Uuid().v4(),
        presetId: product.id,
        description: product.description,
        unitPrice: product.unitPrice,
        quantity: quantity,
      ));
    }
    notifyListeners();
  }

  void addManualItemToCart(String description, double unitPrice, int quantity) {
    _cart.add(CartItem(
      id: const Uuid().v4(),
      presetId: null,
      description: description,
      unitPrice: unitPrice,
      quantity: quantity,
    ));
    notifyListeners();
  }

  void updateCartQuantity(String cartItemId, int quantity) {
    final index = _cart.indexWhere((c) => c.id == cartItemId);
    if (index >= 0) {
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
    _discountPercent = 0.0;
    notifyListeners();
  }

  void setDiscount(double percent) {
    _discountPercent = percent;
    notifyListeners();
  }

  Future<void> finalizeAndSaveReceipt({
    required String customerName,
    required String customerWhatsApp,
    required String paymentMethod,
  }) async {
    if (_cart.isEmpty) return;
    
    // Clear cart after printing/saving order
    clearCart();
  }
}
