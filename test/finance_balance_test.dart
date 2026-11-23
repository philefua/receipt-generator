import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:receipt_generator/features/finance/balance_math.dart';
import 'package:receipt_generator/features/finance/balance_receipt_view.dart';
import 'package:receipt_generator/features/finance/balance_repository.dart';
import 'package:receipt_generator/features/finance/finance_boxes.dart';
import 'package:receipt_generator/features/finance/finance_repository.dart';
import 'package:receipt_generator/models/receipt.dart';

void main() {
  group('BalanceMath (pure)', () {
    test('outstanding = total - deposit - later payments, never below zero', () {
      expect(
          BalanceMath.outstandingMinor(
              totalMinor: 1000000, depositMinor: 400000, paidLaterMinor: 0),
          600000);
      expect(
          BalanceMath.outstandingMinor(
              totalMinor: 1000000, depositMinor: 400000, paidLaterMinor: 250000),
          350000);
      expect(
          BalanceMath.outstandingMinor(
              totalMinor: 1000000, depositMinor: 400000, paidLaterMinor: 700000),
          0);
    });

    test('minor units do not drift', () {
      expect(BalanceMath.toMinor(0.1) + BalanceMath.toMinor(0.2), 30);
      expect(BalanceMath.toMinor(1234.57), 123457);
      expect(BalanceMath.fromMinor(123457), 1234.57);
    });

    test('outstandingBySale sums payments per sale and ignores unknown codes', () {
      final result = BalanceMath.outstandingBySale(
        const [
          SaleSummary(code: 'A', totalMinor: 1000, depositMinor: 300),
          SaleSummary(code: 'B', totalMinor: 500, depositMinor: 500),
        ],
        const [
          PaymentSummary(linkedCode: 'A', amountMinor: 200),
          PaymentSummary(linkedCode: 'A', amountMinor: 100),
          PaymentSummary(linkedCode: 'ZZ', amountMinor: 999),
        ],
      );
      expect(result, {'A': 400, 'B': 0});
    });

    test('validatePayment rejects what the rules forbid', () {
      String? v(bool sale, int owed, int amount) => BalanceMath.validatePayment(
          originalIsSale: sale, outstandingMinor: owed, amountMinor: amount);
      expect(v(true, 1000, 500), isNull);
      expect(v(true, 1000, 1000), isNull);
      expect(v(false, 1000, 500), isNotNull); // not a sale
      expect(v(true, 0, 500), isNotNull); // nothing owed
      expect(v(true, 1000, 0), isNotNull); // zero
      expect(v(true, 1000, -5), isNotNull); // negative
      expect(v(true, 1000, 1001), isNotNull); // more than owed
    });
  });

  group('BalanceRepository', () {
    late Directory dir;
    final repo = BalanceRepository.instance;
    final now = DateTime(2026, 11, 22, 10);

    Future<Receipt> addSale({
      String code = 'ZKq05',
      double total = 10000,
      double deposit = 4000,
    }) async {
      final r = Receipt(
        receiptCode: code,
        issuedAt: DateTime(2026, 11, 17, 10),
        items: [
          ReceiptItem(
              productId: 'p',
              name: 'Banner',
              unitPrice: total,
              quantity: 1,
              lineTotal: total),
        ],
        subtotal: total,
        discountPercent: 0,
        discountAmount: 0,
        totalPayable: total,
        cashierName: 'Front Desk',
        customerName: 'Ada',
        customerWhatsapp: '+2348012345678',
        depositPaid: deposit,
        balanceOwed: total - deposit,
      );
      await Hive.box<Receipt>(BalanceRepository.receiptsBoxName).add(r);
      return r;
    }

    Box<Receipt> receipts() => Hive.box<Receipt>(BalanceRepository.receiptsBoxName);

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('balance_test_');
      Hive.init(dir.path);
      FinanceBoxes.registerAdapters();
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ReceiptItemAdapter());
      if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(ReceiptAdapter());
      await FinanceBoxes.openAll();
      await Hive.openBox<Receipt>(BalanceRepository.receiptsBoxName);
    });

    tearDown(() async {
      await Hive.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('lookup finds the sale and computes what is owed', () async {
      await addSale();
      final look = repo.lookup(' ZKq05 ');
      expect(look.found, isTrue);
      expect(look.totalMinor, 1000000);
      expect(look.alreadyPaidMinor, 400000);
      expect(look.outstandingMinor, 600000);
    });

    test('lookup refuses blank, unknown, wrong-case and balance-receipt codes', () async {
      await addSale();
      expect(repo.lookup('').found, isFalse);
      expect(repo.lookup('NOPE').found, isFalse);
      expect(repo.lookup('zkq05').found, isFalse); // case matters
      final paid = await repo.recordPayment(
          originalCode: 'ZKq05', amount: 100, paymentMethod: 'Cash', now: now);
      expect(paid.ok, isTrue);
      final onBalanceReceipt = repo.lookup(paid.receipt!.receiptCode);
      expect(onBalanceReceipt.found, isFalse);
      expect(onBalanceReceipt.error, contains('balance receipt'));
    });

    test('partial payments reduce the balance until settled, then stop', () async {
      await addSale();

      final p1 = await repo.recordPayment(
          originalCode: 'ZKq05', amount: 2500, paymentMethod: 'Transfer', now: now);
      expect(p1.ok, isTrue);
      expect(p1.receipt!.totalPayable, 2500);
      expect(p1.receipt!.balanceOwed, 3500); // remaining after this payment
      expect(repo.lookup('ZKq05').outstandingMinor, 350000);

      final p2 = await repo.recordPayment(
          originalCode: 'ZKq05', amount: 3500, paymentMethod: 'Cash', now: now);
      expect(p2.ok, isTrue);
      expect(p2.receipt!.balanceOwed, 0);
      expect(repo.lookup('ZKq05').outstandingMinor, 0);

      final p3 = await repo.recordPayment(
          originalCode: 'ZKq05', amount: 1, paymentMethod: 'Cash', now: now);
      expect(p3.ok, isFalse);
      expect(receipts().length, 3); // sale + 2 balance receipts, nothing else
    });

    test('over-payment, zero, negative and blank method are refused', () async {
      await addSale();
      Future<bool> ok(double a, [String m = 'Cash']) async => (await repo
              .recordPayment(
                  originalCode: 'ZKq05', amount: a, paymentMethod: m, now: now))
          .ok;
      expect(await ok(6000.01), isFalse);
      expect(await ok(0), isFalse);
      expect(await ok(-10), isFalse);
      expect(await ok(double.nan), isFalse);
      expect(await ok(100, '  '), isFalse);
      expect((await repo.recordPayment(
              originalCode: 'MISSING', amount: 100, paymentMethod: 'Cash', now: now))
          .ok, isFalse);
      expect(receipts().length, 1);
      expect(repo.lookup('ZKq05').outstandingMinor, 600000);
    });

    test('the original receipt is never changed', () async {
      await addSale();
      await repo.recordPayment(
          originalCode: 'ZKq05', amount: 2500, paymentMethod: 'Cash', now: now);
      final stored = receipts().values.firstWhere((r) => r.receiptCode == 'ZKq05');
      expect(stored.depositPaid, 4000);
      expect(stored.balanceOwed, 6000);
      expect(stored.totalPayable, 10000);
      expect(stored.receiptType, 'sale');
      expect(stored.items.length, 1);
    });

    test('the balance receipt copies the customer and links to the sale', () async {
      await addSale();
      final r = (await repo.recordPayment(
              originalCode: 'ZKq05', amount: 2500, paymentMethod: 'POS', now: now))
          .receipt!;
      expect(r.isBalancePayment, isTrue);
      expect(r.linkedReceiptId, 'ZKq05');
      expect(r.customerName, 'Ada');
      expect(r.customerWhatsapp, '+2348012345678');
      expect(r.paymentMethod, 'POS');
      expect(r.items, isEmpty);
      expect(r.issuedAt, now);
    });

    test('balance receipt numbers: -B suffix, own daily serial, resets each day', () async {
      await addSale();
      final a = await repo.recordPayment(
          originalCode: 'ZKq05', amount: 100, paymentMethod: 'Cash', now: now);
      final b = await repo.recordPayment(
          originalCode: 'ZKq05', amount: 100, paymentMethod: 'Cash', now: now);
      final nextDay = await repo.recordPayment(
          originalCode: 'ZKq05',
          amount: 100,
          paymentMethod: 'Cash',
          now: DateTime(2026, 11, 23, 9));
      expect(a.receipt!.receiptCode, 'ZKv01-B'); // 2026, November, 22nd, serial 01
      expect(b.receipt!.receiptCode, 'ZKv02-B');
      expect(nextDay.receipt!.receiptCode, 'ZKw01-B');
      expect(FinanceRepository.instance.settings.balanceReceiptCounter, 1);
      // Never collides with a sale code (sale codes have no suffix).
      expect(receipts().values.map((r) => r.receiptCode).toSet().length, 4);
    });

    test('the 99 balance receipts a day limit is enforced and saves nothing', () async {
      await addSale();
      final s = FinanceRepository.instance.settings;
      s.balanceReceiptCounterDate = 20261122;
      s.balanceReceiptCounter = 99;
      await FinanceRepository.instance.saveSettings(s);

      final r = await repo.recordPayment(
          originalCode: 'ZKq05', amount: 100, paymentMethod: 'Cash', now: now);
      expect(r.ok, isFalse);
      expect(receipts().length, 1);
    });

    test('openBalances lists only sales that still owe, newest first', () async {
      await addSale(code: 'ZKq05', total: 10000, deposit: 4000);
      await addSale(code: 'ZKr06', total: 5000, deposit: 5000); // paid in full
      await addSale(code: 'ZKs07', total: 3000, deposit: 1000);
      await repo.recordPayment(
          originalCode: 'ZKs07', amount: 2000, paymentMethod: 'Cash', now: now);

      final open = repo.openBalances();
      expect(open.map((o) => o.sale.receiptCode), ['ZKq05']);
      expect(open.single.outstandingMinor, 600000);
    });

    test('balance receipts survive close and reopen', () async {
      await addSale();
      await repo.recordPayment(
          originalCode: 'ZKq05', amount: 2500, paymentMethod: 'Cash', now: now);
      await Hive.box<Receipt>(BalanceRepository.receiptsBoxName).close();
      await Hive.openBox<Receipt>(BalanceRepository.receiptsBoxName);
      expect(repo.lookup('ZKq05').outstandingMinor, 350000);
    });
  });

  group('balance receipt text', () {
    Receipt balanceReceipt({double paid = 2500, double remaining = 3500}) => Receipt(
          receiptCode: 'ZKv01-B',
          issuedAt: DateTime(2026, 11, 22, 9, 5),
          items: const [],
          subtotal: paid,
          discountPercent: 0,
          discountAmount: 0,
          totalPayable: paid,
          cashierName: 'Front Desk',
          customerName: 'Ada',
          paymentMethod: 'Cash',
          depositPaid: paid,
          balanceOwed: remaining,
          receiptType: Receipt.typeBalancePayment,
          linkedReceiptId: 'ZKq05',
        );

    test('previous balance is amount paid plus remaining', () {
      final v = BalanceReceiptView.fromReceipt(balanceReceipt(),
          businessName: 'Printiverse', currency: 'N');
      expect(v.previousMinor, 600000);
      expect(v.paidMinor, 250000);
      expect(v.remainingMinor, 350000);
      expect(v.settled, isFalse);
    });

    test('WhatsApp message carries the required lines', () {
      final msg = BalanceReceiptView.fromReceipt(balanceReceipt(),
              businessName: 'Printiverse', currency: 'N', footnote: ' Thanks! ')
          .whatsappMessage();
      expect(msg, contains('Printiverse'));
      expect(msg, contains('BALANCE PAYMENT'));
      expect(msg, contains('Receipt No: ZKv01-B'));
      expect(msg, contains('Original Receipt: ZKq05'));
      expect(msg, contains('Previous Balance: N6000.00'));
      expect(msg, contains('Amount Paid Now: N2500.00'));
      expect(msg, contains('Remaining Balance: N3500.00'));
      expect(msg, isNot(contains('Fully paid')));
      expect(msg.trim().endsWith('Thanks!'), isTrue);
    });

    test('a settled balance says fully paid', () {
      final msg = BalanceReceiptView.fromReceipt(
              balanceReceipt(paid: 3500, remaining: 0),
              businessName: 'P',
              currency: 'N')
          .whatsappMessage();
      expect(msg, contains('Remaining Balance: N0.00'));
      expect(msg, contains('Fully paid.'));
    });

    test('history subtitle: unchanged for normal sales, informative otherwise', () {
      Receipt sale({required double total, required double deposit, String name = 'Ada'}) =>
          Receipt(
            receiptCode: 'ZKq05',
            issuedAt: DateTime(2026, 11, 17),
            items: const [],
            subtotal: total,
            discountPercent: 0,
            discountAmount: 0,
            totalPayable: total,
            cashierName: 'Front Desk',
            customerName: name,
            depositPaid: deposit,
            balanceOwed: total - deposit,
          );
      String sub(Receipt r, [Map<String, int> m = const {}]) => historySubtitle(
          receipt: r, dateText: '2026-11-17  10:00', currency: 'N', outstandingByCode: m);

      // Exactly the text the page always showed.
      expect(sub(sale(total: 5000, deposit: 5000)), 'Ada\n2026-11-17  10:00 • Cash');
      expect(sub(sale(total: 5000, deposit: 5000, name: '')),
          'Walk-in customer\n2026-11-17  10:00 • Cash');
      // Opened with a balance.
      expect(sub(sale(total: 10000, deposit: 4000), {'ZKq05': 350000}),
          'Ada\n2026-11-17  10:00 • Cash • Balance N3500.00');
      expect(sub(sale(total: 10000, deposit: 4000), {'ZKq05': 0}),
          'Ada\n2026-11-17  10:00 • Cash • Settled');
      // A balance receipt.
      expect(sub(balanceReceipt()),
          'Balance payment for ZKq05 • Ada\n2026-11-17  10:00 • Cash');
    });
  });
}
