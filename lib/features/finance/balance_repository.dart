import 'package:hive/hive.dart';

import '../../models/receipt.dart';
import '../../utils/discount_code_util.dart';
import 'balance_math.dart';
import 'finance_repository.dart';
import 'legacy_link_repository.dart';

/// A sale that still has money owed on it.
class OpenBalance {
  final Receipt sale;
  final int outstandingMinor;

  const OpenBalance({required this.sale, required this.outstandingMinor});
}

/// What the cashier sees after typing or picking an original receipt number.
class BalanceLookup {
  final Receipt? original;
  final int totalMinor;
  final int depositMinor;
  final int paidLaterMinor;
  final int outstandingMinor;
  final String? error;

  const BalanceLookup._({
    this.original,
    this.totalMinor = 0,
    this.depositMinor = 0,
    this.paidLaterMinor = 0,
    this.outstandingMinor = 0,
    this.error,
  });

  factory BalanceLookup.failure(String message) =>
      BalanceLookup._(error: message);

  factory BalanceLookup.found({
    required Receipt original,
    required int totalMinor,
    required int depositMinor,
    required int paidLaterMinor,
    required int outstandingMinor,
  }) =>
      BalanceLookup._(
        original: original,
        totalMinor: totalMinor,
        depositMinor: depositMinor,
        paidLaterMinor: paidLaterMinor,
        outstandingMinor: outstandingMinor,
      );

  bool get found => original != null && error == null;

  /// Deposit plus earlier balance payments.
  int get alreadyPaidMinor => depositMinor + paidLaterMinor;
}

class BalanceSaveResult {
  final Receipt? receipt;
  final String? error;

  const BalanceSaveResult._({this.receipt, this.error});

  factory BalanceSaveResult.success(Receipt receipt) =>
      BalanceSaveResult._(receipt: receipt);

  factory BalanceSaveResult.failure(String message) =>
      BalanceSaveResult._(error: message);

  bool get ok => receipt != null;
}

/// Finds sales that owe money and records balance payments as new receipts.
///
/// A balance payment is its own receipt (type balance_payment) linked to the
/// original sale by receipt number. The original receipt is never changed,
/// outstanding is computed from the receipts every time, and the sale
/// receipt counter is not touched: balance receipts have their own daily
/// serial, kept in the finance settings.
class BalanceRepository {
  BalanceRepository._();
  static final BalanceRepository instance = BalanceRepository._();

  /// The box the app already uses for receipts. Receipts are only ever added,
  /// never edited or deleted.
  static const String receiptsBoxName = 'receipts_box';

  /// Appended to the sale-style code, e.g. ZKq01-B.
  static const String codeSuffix = '-B';

  Box<Receipt>? get _receipts {
    try {
      return Hive.isBoxOpen(receiptsBoxName)
          ? Hive.box<Receipt>(receiptsBoxName)
          : null;
    } catch (_) {
      return null;
    }
  }

  /// True when balance payments can be looked up and saved on this device.
  bool get isReady => _receipts != null && FinanceRepository.instance.isReady;

  static Iterable<SaleSummary> _sales(Iterable<Receipt> all) => all
      .where((r) => !r.isBalancePayment)
      .map((r) => SaleSummary(
            code: r.receiptCode,
            totalMinor: BalanceMath.toMinor(r.totalPayable),
            depositMinor: BalanceMath.toMinor(r.depositPaid),
          ));

  static Iterable<PaymentSummary> _payments(Iterable<Receipt> all) => all
      .where((r) => r.isBalancePayment && r.linkedReceiptId != null)
      .map((r) => PaymentSummary(
            linkedCode: r.linkedReceiptId!,
            amountMinor: BalanceMath.toMinor(r.totalPayable),
          ));

  /// Outstanding balance per sale code for the given receipts (the history
  /// page passes the list it already has, so this is one pass).
  ///
  /// Old hand-typed balance receipts that the manager (or the matcher) has
  /// linked count as payments on their original sale, and a linked balance
  /// receipt does not count as a second debt of its own.
  static Map<String, int> outstandingByCode(Iterable<Receipt> all) {
    final list = all.toList();
    final legacy = LegacyLinkRepository.instance.adjustmentsFor(list);
    final map = BalanceMath.outstandingBySale(
      _sales(list),
      [..._payments(list), ...legacy.payments],
    );
    for (final code in legacy.clearedOwn) {
      if (map.containsKey(code)) map[code] = 0;
    }
    return map;
  }

  /// Looks up the original sale by its exact receipt number. Letters are
  /// case-sensitive on purpose: the code format uses capital and small
  /// letters to mean different dates.
  BalanceLookup lookup(String rawCode) {
    final box = _receipts;
    if (box == null) {
      return BalanceLookup.failure('Receipts are not available on this device.');
    }
    final code = rawCode.trim();
    if (code.isEmpty) {
      return BalanceLookup.failure('Enter the original receipt number.');
    }

    final legacy = LegacyLinkRepository.instance.adjustmentsFor(box.values);

    Receipt? original;
    var paidLater = 0;
    for (final r in box.values) {
      if (r.receiptCode == code) original = r;
      if (r.isBalancePayment && r.linkedReceiptId == code) {
        paidLater += BalanceMath.toMinor(r.totalPayable);
      }
    }
    // Old typed balance receipts linked to this sale.
    for (final p in legacy.payments) {
      if (p.linkedCode == code) paidLater += p.amountMinor;
    }
    if (original == null) {
      return BalanceLookup.failure(
          'No receipt found with the number $code. Check the letters '
          '(capital and small letters matter) or pick it from the list.');
    }
    if (original.isBalancePayment || legacy.linkedCodes.contains(code)) {
      return BalanceLookup.failure(
          '$code is a balance receipt. Enter the number of the original sale receipt.');
    }

    final total = BalanceMath.toMinor(original.totalPayable);
    final deposit = BalanceMath.toMinor(original.depositPaid);
    return BalanceLookup.found(
      original: original,
      totalMinor: total,
      depositMinor: deposit,
      paidLaterMinor: paidLater,
      outstandingMinor: BalanceMath.outstandingMinor(
        totalMinor: total,
        depositMinor: deposit,
        paidLaterMinor: paidLater,
      ),
    );
  }

  /// Sales that still owe money, newest first.
  List<OpenBalance> openBalances() {
    final box = _receipts;
    if (box == null) return const [];
    final all = box.values.toList();
    final outstanding = outstandingByCode(all);
    final list = <OpenBalance>[
      for (final r in all)
        if (!r.isBalancePayment && (outstanding[r.receiptCode] ?? 0) > 0)
          OpenBalance(sale: r, outstandingMinor: outstanding[r.receiptCode]!),
    ]..sort((a, b) => b.sale.issuedAt.compareTo(a.sale.issuedAt));
    return list;
  }

  static int _dayKey(DateTime d) => d.year * 10000 + d.month * 100 + d.day;

  /// Records a balance payment against [originalCode] as a new receipt.
  /// Returns the saved receipt, or a plain-English reason it was refused.
  Future<BalanceSaveResult> recordPayment({
    required String originalCode,
    required double amount,
    required String paymentMethod,
    String cashierName = 'Front Desk',
    DateTime? now,
  }) async {
    final box = _receipts;
    if (box == null || !FinanceRepository.instance.isReady) {
      return BalanceSaveResult.failure(
          'Balance payments are not available on this device.');
    }
    if (amount.isNaN || amount.isInfinite) {
      return BalanceSaveResult.failure('Enter a valid amount.');
    }
    final method = paymentMethod.trim();
    if (method.isEmpty) {
      return BalanceSaveResult.failure('Choose how it was paid.');
    }

    final look = lookup(originalCode);
    if (!look.found) {
      return BalanceSaveResult.failure(look.error ?? 'Receipt not found.');
    }
    final original = look.original!;

    final amountMinor = BalanceMath.toMinor(amount);
    final problem = BalanceMath.validatePayment(
      originalIsSale: !original.isBalancePayment,
      outstandingMinor: look.outstandingMinor,
      amountMinor: amountMinor,
    );
    if (problem != null) return BalanceSaveResult.failure(problem);

    // Own daily serial, 1 to 99, never shared with the sale counter.
    final clock = now ?? DateTime.now();
    final settings = FinanceRepository.instance.settings;
    final today = _dayKey(clock);
    var serial =
        settings.balanceReceiptCounterDate == today ? settings.balanceReceiptCounter : 0;
    serial += 1;
    if (serial > 99) {
      return BalanceSaveResult.failure(
          'The limit of 99 balance receipts for one day has been reached.');
    }

    final code = DiscountCodeUtil.generateReceiptCode(
          date: clock,
          dailyOrderNumber: serial,
        ) +
        codeSuffix;
    if (box.values.any((r) => r.receiptCode == code)) {
      return BalanceSaveResult.failure(
          'Receipt number $code is already in use. Please try again.');
    }

    // Save the counter first: a skipped number is harmless, a repeated one is not.
    settings.balanceReceiptCounterDate = today;
    settings.balanceReceiptCounter = serial;
    await FinanceRepository.instance.saveSettings(settings);

    final remaining = look.outstandingMinor - amountMinor;
    final receipt = Receipt(
      receiptCode: code,
      issuedAt: clock,
      items: const [],
      subtotal: BalanceMath.fromMinor(amountMinor),
      discountPercent: 0,
      discountAmount: 0,
      totalPayable: BalanceMath.fromMinor(amountMinor),
      cashierName: cashierName,
      isLocked: true,
      customerName: original.customerName,
      customerWhatsapp: original.customerWhatsapp,
      paymentMethod: method,
      couponReference: '',
      depositPaid: BalanceMath.fromMinor(amountMinor),
      balanceOwed: BalanceMath.fromMinor(remaining),
      receiptType: Receipt.typeBalancePayment,
      linkedReceiptId: original.receiptCode,
    );
    await box.add(receipt);
    return BalanceSaveResult.success(receipt);
  }
}
