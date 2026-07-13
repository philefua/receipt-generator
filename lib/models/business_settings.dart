import 'package:hive/hive.dart';

part 'business_settings.g.dart';

@HiveType(typeId: 0)
class BusinessSettings extends HiveObject {
  @HiveField(0)
  String businessName;

  @HiveField(1)
  String address;

  @HiveField(2)
  String phone;

  @HiveField(3)
  String? logoPath;

  @HiveField(4)
  String currencySymbol;

  @HiveField(5)
  String managerPasswordHash;

  @HiveField(6)
  int lastReceiptCounterDate;

  @HiveField(7)
  int dailyReceiptCounter;

  @HiveField(8)
  String whatsapp;

  @HiveField(9)
  String website;

  @HiveField(10)
  String instagram;

  @HiveField(11)
  String facebook;

  @HiveField(12)
  String footnote;

  BusinessSettings({
    this.businessName = 'My Business',
    this.address = '',
    this.phone = '',
    this.logoPath,
    this.currencySymbol = '\$',
    required this.managerPasswordHash,
    this.lastReceiptCounterDate = 0,
    this.dailyReceiptCounter = 0,
    this.whatsapp = '',
    this.website = '',
    this.instagram = '',
    this.facebook = '',
    this.footnote = '',
  });
}