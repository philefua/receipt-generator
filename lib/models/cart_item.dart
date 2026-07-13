import 'product_preset.dart';

class CartItem {
  final ProductPreset product;
  int quantity;

  CartItem({
    required this.product,
    required this.quantity,
  });

  double get lineTotal => product.unitPrice * quantity;
}
