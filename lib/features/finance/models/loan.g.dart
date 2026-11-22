// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'loan.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LoanAdapter extends TypeAdapter<Loan> {
  @override
  final int typeId = 12;

  @override
  Loan read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Loan(
      id: fields[0] as String,
      lenderName: fields[1] as String,
      lenderType: fields[2] as String,
      dateReceived: fields[3] as DateTime,
      principal: fields[4] as double,
      interestRatePercent: fields[5] as double?,
      termMonths: fields[6] as int?,
      receivedInto: fields[7] as String,
      notes: fields[8] as String,
      isOpeningBalance: fields[9] as bool,
      createdAt: fields[10] as DateTime,
      voidedAt: fields[11] as DateTime?,
      voidReason: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Loan obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.lenderName)
      ..writeByte(2)
      ..write(obj.lenderType)
      ..writeByte(3)
      ..write(obj.dateReceived)
      ..writeByte(4)
      ..write(obj.principal)
      ..writeByte(5)
      ..write(obj.interestRatePercent)
      ..writeByte(6)
      ..write(obj.termMonths)
      ..writeByte(7)
      ..write(obj.receivedInto)
      ..writeByte(8)
      ..write(obj.notes)
      ..writeByte(9)
      ..write(obj.isOpeningBalance)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.voidedAt)
      ..writeByte(12)
      ..write(obj.voidReason);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoanAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
