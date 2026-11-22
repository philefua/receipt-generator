// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'receipt_link.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ReceiptLinkAdapter extends TypeAdapter<ReceiptLink> {
  @override
  final int typeId = 9;

  @override
  ReceiptLink read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ReceiptLink(
      id: fields[0] as String,
      kind: fields[1] as String,
      receiptCode: fields[2] as String,
      originalReceiptCode: fields[3] as String,
      amount: fields[4] as double,
      reason: fields[5] as String,
      createdAt: fields[6] as DateTime,
      voidedAt: fields[7] as DateTime?,
      voidReason: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ReceiptLink obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.kind)
      ..writeByte(2)
      ..write(obj.receiptCode)
      ..writeByte(3)
      ..write(obj.originalReceiptCode)
      ..writeByte(4)
      ..write(obj.amount)
      ..writeByte(5)
      ..write(obj.reason)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.voidedAt)
      ..writeByte(8)
      ..write(obj.voidReason);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceiptLinkAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
