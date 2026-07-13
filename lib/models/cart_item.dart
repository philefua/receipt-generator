class CartItem {
  final String id;
  final String? presetId;
  final String name;
  final double unitPrice;
  int quantity;

  CartItem({
    required this.id,
    this.presetId,
    required this.name,
    required this.unitPrice,
    this.quantity = 1,
  });

  double get lineTotal => unitPrice * quantity;
}