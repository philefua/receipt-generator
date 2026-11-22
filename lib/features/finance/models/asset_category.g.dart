// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'asset_category.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AssetCategoryAdapter extends TypeAdapter<AssetCategory> {
  @override
  final int typeId = 8;

  @override
  AssetCategory read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AssetCategory(
      id: fields[0] as String,
      name: fields[1] as String,
      defaultUsefulLifeMonths: fields[2] as int,
      archived: fields[3] as bool,
      sortOrder: fields[4] as int,
      createdAt: fields[5] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, AssetCategory obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.defaultUsefulLifeMonths)
      ..writeByte(3)
      ..write(obj.archived)
      ..writeByte(4)
      ..write(obj.sortOrder)
      ..writeByte(5)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AssetCategoryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
