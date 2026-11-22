// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  final int typeId = 14;

  @override
  Expense read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Expense(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      createdAt: fields[2] as DateTime,
      amount: fields[3] as double,
      categoryId: fields[4] as String,
      categoryType: fields[5] as String,
      paidFrom: fields[6] as String,
      description: fields[7] as String,
      vendor: fields[8] as String?,
      inputVat: fields[9] as double?,
      whtAmount: fields[10] as double?,
      createdByRole: fields[11] as String,
      voidedAt: fields[12] as DateTime?,
      voidReason: fields[13] as String?,
      voidedBy: fields[14] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Expense obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.createdAt)
      ..writeByte(3)
      ..write(obj.amount)
      ..writeByte(4)
      ..write(obj.categoryId)
      ..writeByte(5)
      ..write(obj.categoryType)
      ..writeByte(6)
      ..write(obj.paidFrom)
      ..writeByte(7)
      ..write(obj.description)
      ..writeByte(8)
      ..write(obj.vendor)
      ..writeByte(9)
      ..write(obj.inputVat)
      ..writeByte(10)
      ..write(obj.whtAmount)
      ..writeByte(11)
      ..write(obj.createdByRole)
      ..writeByte(12)
      ..write(obj.voidedAt)
      ..writeByte(13)
      ..write(obj.voidReason)
      ..writeByte(14)
      ..write(obj.voidedBy);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExpenseAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
