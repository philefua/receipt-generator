// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_preset.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProductPresetAdapter extends TypeAdapter<ProductPreset> {
  @override
  final int typeId = 1;

  @override
  ProductPreset read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ProductPreset(
      id: fields[0] as String,
      name: fields[1] as String,
      price: fields[2] as double,
      category: fields[3] as String?,
      isActive: fields[4] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, ProductPreset obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.price)
      ..writeByte(3)
      ..write(obj.category)
      ..writeByte(4)
      ..write(obj.isActive);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductPresetAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
