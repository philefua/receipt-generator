// ---------------------------------------------------------------------
  // Cart (Cashier Frontend)
  // ---------------------------------------------------------------------

  List<CartItem> get cart => List.unmodifiable(_cart);

  double get discountPercent => _discountPercent;

  void addToCart(ProductPreset product, {int quantity = 1}) {
    final existingIndex =
        _cart.indexWhere((c) => c.presetId == product.id);
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

  // ---------------------------------------------------------------------
  // Calculations
  // ---------------------------------------------------------------------

  double get subtotal =>
      _cart.fold(0.0, (sum, item) => sum + item.lineTotal);

  double get discountAmount =>
      double.parse((subtotal * (_discountPercent / 100)).toStringAsFixed(2));

  double get totalPayable =>
      double.parse((subtotal - discountAmount).toStringAsFixed(2));

  // ---------------------------------------------------------------------
  // Finalizing & Saving Receipts (IMMUTABLE — write-once)
  // ---------------------------------------------------------------------

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

    final receipt = Receipt(
      receiptCode: code,
      issuedAt: now,
      items: frozenItems,
      subtotal: subtotal,
      discountPercent: _discountPercent,
      discountAmount: discountAmount,
      totalPayable: totalPayable,
      cashierName: cashierName,
      isLocked: true,
      customerName: customerName.trim(),
      customerWhatsapp: customerWhatsapp.trim(),
      paymentMethod: paymentMethod,
    );

    await _receiptsBox.add(receipt);
    await settings.save();

    clearCart();
    return receipt;
  }