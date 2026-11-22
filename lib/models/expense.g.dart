// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ExpenseAdapter extends TypeAdapter<Expense> {
  @override
  final int typeId = 5;

  @override
  Expense read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Expense(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      voucher: fields[2] as String,
      vendor: fields[3] as String,
      description: fields[4] as String,
      costType: fields[5] as String,
      category: fields[6] as String,
      netAmount: fields[7] as double,
      inputVat: fields[8] as double,
      whtDeducted: fields[9] as double,
      paymentAccount: fields[10] as String,
      receiptStatus: fields[11] as String,
      recordedBy: fields[12] as String,
      notes: fields[13] as String,
      isVoided: fields[14] as bool,
      recordedAt: fields[15] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, Expense obj) {
    writer
      ..writeByte(16)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.voucher)
      ..writeByte(3)
      ..write(obj.vendor)
      ..writeByte(4)
      ..write(obj.description)
      ..writeByte(5)
      ..write(obj.costType)
      ..writeByte(6)
      ..write(obj.category)
      ..writeByte(7)
      ..write(obj.netAmount)
      ..writeByte(8)
      ..write(obj.inputVat)
      ..writeByte(9)
      ..write(obj.whtDeducted)
      ..writeByte(10)
      ..write(obj.paymentAccount)
      ..writeByte(11)
      ..write(obj.receiptStatus)
      ..writeByte(12)
      ..write(obj.recordedBy)
      ..writeByte(13)
      ..write(obj.notes)
      ..writeByte(14)
      ..write(obj.isVoided)
      ..writeByte(15)
      ..write(obj.recordedAt);
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
