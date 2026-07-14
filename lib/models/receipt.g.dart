// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipt.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReceiptItemAdapter extends TypeAdapter<ReceiptItem> {
  @override
  final int typeId = 2;

  @override
  ReceiptItem read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReceiptItem(
      productId: fields[0] as String,
      name: fields[1] as String,
      unitPrice: fields[2] as double,
      quantity: fields[3] as int,
      lineTotal: fields[4] as double,
    );
  }

  @override
  void write(BinaryWriter writer, ReceiptItem obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.productId)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.unitPrice)
      ..writeByte(3)
      ..write(obj.quantity)
      ..writeByte(4)
      ..write(obj.lineTotal);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiptItemAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ReceiptAdapter extends TypeAdapter<Receipt> {
  @override
  final int typeId = 3;

  @override
  Receipt read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Receipt(
      receiptCode: fields[0] as String,
      issuedAt: fields[1] as DateTime,
      items: (fields[2] as List).cast<ReceiptItem>(),
      subtotal: fields[3] as double,
      discountPercent: fields[4] as double,
      discountAmount: fields[5] as double,
      totalPayable: fields[6] as double,
      cashierName: fields[7] as String,
      isLocked: fields[8] as bool,
      customerName: fields[9] as String,
      customerWhatsapp: fields[10] as String,
      paymentMethod: fields[11] as String,
      couponReference: fields[12] as String,
      depositPaid: fields[13] as double,
      balanceOwed: fields[14] as double,
    );
  }

  @override
  void write(BinaryWriter writer, Receipt obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.receiptCode)
      ..writeByte(1)
      ..write(obj.issuedAt)
      ..writeByte(2)
      ..write(obj.items)
      ..writeByte(3)
      ..write(obj.subtotal)
      ..writeByte(4)
      ..write(obj.discountPercent)
      ..writeByte(5)
      ..write(obj.discountAmount)
      ..writeByte(6)
      ..write(obj.totalPayable)
      ..writeByte(7)
      ..write(obj.cashierName)
      ..writeByte(8)
      ..write(obj.isLocked)
      ..writeByte(9)
      ..write(obj.customerName)
      ..writeByte(10)
      ..write(obj.customerWhatsapp)
      ..writeByte(11)
      ..write(obj.paymentMethod)
      ..writeByte(12)
      ..write(obj.couponReference)
      ..writeByte(13)
      ..write(obj.depositPaid)
      ..writeByte(14)
      ..write(obj.balanceOwed);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiptAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
