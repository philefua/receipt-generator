// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stock_count.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class StockCountAdapter extends TypeAdapter<StockCount> {
  @override
  final int typeId = 10;

  @override
  StockCount read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return StockCount(
      id: fields[0] as String,
      date: fields[1] as DateTime,
      value: fields[2] as double,
      note: fields[3] as String,
      createdAt: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, StockCount obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.date)
      ..writeByte(2)
      ..write(obj.value)
      ..writeByte(3)
      ..write(obj.note)
      ..writeByte(4)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockCountAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
