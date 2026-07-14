// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'business_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BusinessSettingsAdapter extends TypeAdapter<BusinessSettings> {
  @override
  final int typeId = 0;

  @override
  BusinessSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BusinessSettings(
      businessName: fields[0] as String,
      address: fields[1] as String,
      phone: fields[2] as String,
      logoPath: fields[3] as String?,
      currencySymbol: fields[4] as String,
      managerPasswordHash: fields[5] as String,
      lastReceiptCounterDate: fields[6] as int,
      dailyReceiptCounter: fields[7] as int,
      whatsapp: fields[8] as String,
      website: fields[9] as String,
      instagram: fields[10] as String,
      facebook: fields[11] as String,
      footnote: fields[12] as String,
    );
  }

  @override
  void write(BinaryWriter writer, BusinessSettings obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.businessName)
      ..writeByte(1)
      ..write(obj.address)
      ..writeByte(2)
      ..write(obj.phone)
      ..writeByte(3)
      ..write(obj.logoPath)
      ..writeByte(4)
      ..write(obj.currencySymbol)
      ..writeByte(5)
      ..write(obj.managerPasswordHash)
      ..writeByte(6)
      ..write(obj.lastReceiptCounterDate)
      ..writeByte(7)
      ..write(obj.dailyReceiptCounter)
      ..writeByte(8)
      ..write(obj.whatsapp)
      ..writeByte(9)
      ..write(obj.website)
      ..writeByte(10)
      ..write(obj.instagram)
      ..writeByte(11)
      ..write(obj.facebook)
      ..writeByte(12)
      ..write(obj.footnote);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BusinessSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
