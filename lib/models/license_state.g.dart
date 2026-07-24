// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'license_state.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class LicenseStateAdapter extends TypeAdapter<LicenseState> {
  @override
  final int typeId = 4;

  @override
  LicenseState read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return LicenseState()
      ..highWaterMarkUtcMillis = fields[0] as int?
      ..installTimestampUtcMillis = fields[1] as int?
      ..trialEndUtcMillis = fields[2] as int?
      ..subscriptionEndUtcMillis = fields[3] as int?
      ..isLifetime = fields[4] as bool
      ..activationHistory = (fields[5] as List).cast<String>()
      ..hasSucceededRegistryCheck = fields[6] as bool
      ..lastRegistryCheckInUtcMillis = fields[7] as int?;
  }

  @override
  void write(BinaryWriter writer, LicenseState obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.highWaterMarkUtcMillis)
      ..writeByte(1)
      ..write(obj.installTimestampUtcMillis)
      ..writeByte(2)
      ..write(obj.trialEndUtcMillis)
      ..writeByte(3)
      ..write(obj.subscriptionEndUtcMillis)
      ..writeByte(4)
      ..write(obj.isLifetime)
      ..writeByte(5)
      ..write(obj.activationHistory)
      ..writeByte(6)
      ..write(obj.hasSucceededRegistryCheck)
      ..writeByte(7)
      ..write(obj.lastRegistryCheckInUtcMillis);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LicenseStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
