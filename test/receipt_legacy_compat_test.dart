import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:receipt_generator/models/receipt.dart';

/// A receipt exactly as it was stored BEFORE phase 5: 15 fields, 0 to 14.
class _LegacyReceipt {
  final String receiptCode;
  final DateTime issuedAt;
  final List<ReceiptItem> items;
  final double total;
  final String customerName;
  final String customerWhatsapp;
  final double deposit;
  final double balance;

  _LegacyReceipt({
    required this.receiptCode,
    required this.issuedAt,
    required this.items,
    required this.total,
    required this.customerName,
    required this.customerWhatsapp,
    required this.deposit,
    required this.balance,
  });
}

/// The old ReceiptAdapter's write(), copied from the pre-phase-5 generated
/// file. It writes 15 fields and knows nothing about fields 15 and 16.
class _LegacyReceiptAdapter extends TypeAdapter<_LegacyReceipt> {
  @override
  final int typeId = 3;

  @override
  _LegacyReceipt read(BinaryReader reader) => throw UnimplementedError();

  @override
  void write(BinaryWriter writer, _LegacyReceipt obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.receiptCode)
      ..writeByte(1)
      ..write(obj.issuedAt)
      ..writeByte(2)
      ..write(obj.items)
      ..writeByte(3)
      ..write(obj.total)
      ..writeByte(4)
      ..write(0.0)
      ..writeByte(5)
      ..write(0.0)
      ..writeByte(6)
      ..write(obj.total)
      ..writeByte(7)
      ..write('Front Desk')
      ..writeByte(8)
      ..write(true)
      ..writeByte(9)
      ..write(obj.customerName)
      ..writeByte(10)
      ..write(obj.customerWhatsapp)
      ..writeByte(11)
      ..write('Cash')
      ..writeByte(12)
      ..write('')
      ..writeByte(13)
      ..write(obj.deposit)
      ..writeByte(14)
      ..write(obj.balance);
  }
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('receipt_legacy_');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    Hive.resetAdapters();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('receipts saved before phase 5 still open and read back as sales', () async {
    // 1. Store a receipt using the OLD layout.
    Hive.registerAdapter(ReceiptItemAdapter());
    Hive.registerAdapter(_LegacyReceiptAdapter());
    final legacyBox = await Hive.openBox('legacy_receipts');
    await legacyBox.add(_LegacyReceipt(
      receiptCode: 'ZKq05',
      issuedAt: DateTime(2026, 11, 17, 10, 30),
      items: const [
        ReceiptItem(
            productId: 'p1',
            name: 'Banner',
            unitPrice: 10000,
            quantity: 1,
            lineTotal: 10000),
      ],
      total: 10000,
      customerName: 'Ada',
      customerWhatsapp: '+2348012345678',
      deposit: 4000,
      balance: 6000,
    ));
    await legacyBox.close();

    // 2. Open the same file with the NEW adapter.
    Hive.resetAdapters();
    Hive.registerAdapter(ReceiptItemAdapter());
    Hive.registerAdapter(ReceiptAdapter());
    final box = await Hive.openBox<Receipt>('legacy_receipts');

    final r = box.values.single;
    expect(r.receiptCode, 'ZKq05');
    expect(r.totalPayable, 10000);
    expect(r.depositPaid, 4000);
    expect(r.balanceOwed, 6000);
    expect(r.customerName, 'Ada');
    expect(r.items.single.name, 'Banner');
    // New fields get their defaults: an old receipt is a sale.
    expect(r.receiptType, 'sale');
    expect(r.linkedReceiptId, isNull);
    expect(r.isBalancePayment, isFalse);
  });

  test('new receipts keep their type and link after close and reopen', () async {
    Hive.registerAdapter(ReceiptItemAdapter());
    Hive.registerAdapter(ReceiptAdapter());
    var box = await Hive.openBox<Receipt>('new_receipts');
    await box.add(Receipt(
      receiptCode: 'ZKv01-B',
      issuedAt: DateTime(2026, 11, 22, 9),
      items: const [],
      subtotal: 2500,
      discountPercent: 0,
      discountAmount: 0,
      totalPayable: 2500,
      cashierName: 'Front Desk',
      depositPaid: 2500,
      balanceOwed: 3500,
      receiptType: Receipt.typeBalancePayment,
      linkedReceiptId: 'ZKq05',
    ));
    await box.close();

    box = await Hive.openBox<Receipt>('new_receipts');
    final r = box.values.single;
    expect(r.isBalancePayment, isTrue);
    expect(r.linkedReceiptId, 'ZKq05');
    expect(r.balanceOwed, 3500);
    expect(r.items, isEmpty);
  });
}
