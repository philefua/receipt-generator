// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finance_settings.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FinanceSettingsAdapter extends TypeAdapter<FinanceSettings> {
  @override
  final int typeId = 6;

  @override
  FinanceSettings read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return FinanceSettings(
      allowCashierExpenses: fields[0] as bool,
      financialYearStartMonth: fields[1] as int,
      taxId: fields[2] as String,
      vatEnabled: fields[3] as bool,
      vatRatePercent: fields[4] as double,
      estimatedTaxRatePercent: fields[5] as double,
      openingCashBalance: fields[6] as double,
      openingCashDate: fields[7] as DateTime?,
      capitalisationThreshold: fields[8] as double,
      balanceReceiptCounter: fields[9] as int,
      balanceReceiptCounterDate: fields[10] as int,
      paidFromOptions: (fields[11] as List).cast<String>(),
      defaultsSeeded: fields[12] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, FinanceSettings obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.allowCashierExpenses)
      ..writeByte(1)
      ..write(obj.financialYearStartMonth)
      ..writeByte(2)
      ..write(obj.taxId)
      ..writeByte(3)
      ..write(obj.vatEnabled)
      ..writeByte(4)
      ..write(obj.vatRatePercent)
      ..writeByte(5)
      ..write(obj.estimatedTaxRatePercent)
      ..writeByte(6)
      ..write(obj.openingCashBalance)
      ..writeByte(7)
      ..write(obj.openingCashDate)
      ..writeByte(8)
      ..write(obj.capitalisationThreshold)
      ..writeByte(9)
      ..write(obj.balanceReceiptCounter)
      ..writeByte(10)
      ..write(obj.balanceReceiptCounterDate)
      ..writeByte(11)
      ..write(obj.paidFromOptions)
      ..writeByte(12)
      ..write(obj.defaultsSeeded);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FinanceSettingsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
