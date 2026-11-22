// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asset.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssetAdapter extends TypeAdapter<Asset> {
  @override
  final int typeId = 11;

  @override
  Asset read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Asset(
      id: fields[0] as String,
      name: fields[1] as String,
      categoryId: fields[2] as String,
      purchaseDate: fields[3] as DateTime,
      cost: fields[4] as double,
      paymentMethod: fields[5] as String,
      vendor: fields[6] as String?,
      usefulLifeMonths: fields[7] as int,
      residualValue: fields[8] as double,
      method: fields[9] as String,
      annualRate: fields[10] as double?,
      isOpeningBalance: fields[11] as bool,
      status: fields[12] as String,
      retiredDate: fields[13] as DateTime?,
      disposalProceeds: fields[14] as double?,
      notes: fields[15] as String,
      createdAt: fields[16] as DateTime,
      voidedAt: fields[17] as DateTime?,
      voidReason: fields[18] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, Asset obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.categoryId)
      ..writeByte(3)
      ..write(obj.purchaseDate)
      ..writeByte(4)
      ..write(obj.cost)
      ..writeByte(5)
      ..write(obj.paymentMethod)
      ..writeByte(6)
      ..write(obj.vendor)
      ..writeByte(7)
      ..write(obj.usefulLifeMonths)
      ..writeByte(8)
      ..write(obj.residualValue)
      ..writeByte(9)
      ..write(obj.method)
      ..writeByte(10)
      ..write(obj.annualRate)
      ..writeByte(11)
      ..write(obj.isOpeningBalance)
      ..writeByte(12)
      ..write(obj.status)
      ..writeByte(13)
      ..write(obj.retiredDate)
      ..writeByte(14)
      ..write(obj.disposalProceeds)
      ..writeByte(15)
      ..write(obj.notes)
      ..writeByte(16)
      ..write(obj.createdAt)
      ..writeByte(17)
      ..write(obj.voidedAt)
      ..writeByte(18)
      ..write(obj.voidReason);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
