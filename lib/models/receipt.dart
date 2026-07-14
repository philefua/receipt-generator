import 'package:hive/hive.dart';

part 'receipt.g.dart';

@HiveType(typeId: 2)
class ReceiptItem {
  @HiveField(0)
  final String productId;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final double unitPrice;

  @HiveField(3)
  final int quantity;

  @HiveField(4)
  final double lineTotal;

  const ReceiptItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
  });
}

@HiveType(typeId: 3)
class Receipt extends HiveObject {
  @HiveField(0)
  final String receiptCode;

  @HiveField(1)
  final DateTime issuedAt;

  @HiveField(2)
  final List<ReceiptItem> items;

  @HiveField(3)
  final double subtotal;

  @HiveField(4)
  final double discountPercent;

  @HiveField(5)
  final double discountAmount;

  @HiveField(6)
  final double totalPayable;

  @HiveField(7)
  final String cashierName;

  @HiveField(8)
  final bool isLocked;

  @HiveField(9)
  final String customerName;

  @HiveField(10)
  final String customerWhatsapp;

  @HiveField(11)
  final String paymentMethod;

  @HiveField(12)
  final String couponReference;

  @HiveField(13)
  final double depositPaid;

  @HiveField(14)
  final double balanceOwed;

  Receipt({
    required this.receiptCode,
    required this.issuedAt,
    required this.items,
    required this.subtotal,
    required this.discountPercent,
    required this.discountAmount,
    required this.totalPayable,
    required this.cashierName,
    this.isLocked = true,
    this.customerName = '',
    this.customerWhatsapp = '',
    this.paymentMethod = 'Cash',
    this.couponReference = '',
    this.depositPaid = 0,
    this.balanceOwed = 0,
  });
}