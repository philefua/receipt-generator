import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../models/receipt.dart';
import 'balance_math.dart';
import 'balance_repository.dart';
import 'finance_boxes.dart';
import 'models/receipt_link.dart';
import 'writeoff_math.dart';

/// Records and voids write-offs ("Settle with adjustment").
///
/// Reads receipts, never changes them: a write-off is a `writeoff` record in
/// the receipt_links box. Nothing is ever deleted.
class SettlementRepository {
  SettlementRepository._();
  static final SettlementRepository instance = SettlementRepository._();

  Box<Receipt>? get receiptsBox {
    try {
      return Hive.isBoxOpen(BalanceRepository.receiptsBoxName)
          ? Hive.box<Receipt>(BalanceRepository.receiptsBoxName)
          : null;
    } catch (_) {
      return null;
    }
  }

  Box<ReceiptLink>? get linksBox {
    try {
      return Hive.isBoxOpen(FinanceBoxes.receiptLinksBox)
          ? Hive.box<ReceiptLink>(FinanceBoxes.receiptLinksBox)
          : null;
    } catch (_) {
      return null;
    }
  }

  bool get isReady => receiptsBox != null && linksBox != null;

  /// Sales that still owe money, newest first.
  List<OpenBalance> openBalances() => BalanceRepository.instance.openBalances();

  /// Every write-off record, newest first, including voided ones.
  List<ReceiptLink> writeoffs() {
    final box = linksBox;
    if (box == null) return const [];
    return [
      for (final l in box.values)
        if (l.kind == ReceiptLink.kindWriteoff) l,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Writes off [amount] on the sale [receiptCode]. Returns null on success,
  /// or a plain-English reason it was refused.
  Future<String?> writeOff({
    required String receiptCode,
    required double amount,
    required String reason,
    DateTime? now,
  }) async {
    final box = linksBox;
    final receipts = receiptsBox;
    if (box == null || receipts == null) {
      return 'Settlements are not available on this device.';
    }
    if (amount.isNaN || amount.isInfinite) return 'Enter a valid amount.';

    final code = receiptCode.trim();
    final all = receipts.values.toList();
    Receipt? receipt;
    for (final r in all) {
      if (r.receiptCode == code) receipt = r;
    }
    if (receipt == null) return 'Receipt not found.';

    final outstanding = BalanceRepository.outstandingByCode(all)[code] ?? 0;
    final amountMinor = BalanceMath.toMinor(amount);
    final problem = WriteoffMath.validate(
      isSale: !receipt.isBalancePayment,
      outstandingMinor: outstanding,
      amountMinor: amountMinor,
      reason: reason,
    );
    if (problem != null) return problem;

    final link = ReceiptLink(
      id: const Uuid().v4(),
      kind: ReceiptLink.kindWriteoff,
      receiptCode: code,
      originalReceiptCode: code,
      amount: BalanceMath.fromMinor(amountMinor),
      reason: reason.trim(),
      createdAt: now ?? DateTime.now(),
    );
    await box.put(link.id, link);
    return null;
  }

  /// Voids a write-off. The record stays; the balance owed goes back up.
  Future<String?> voidWriteoff(String id, String reason) async {
    final box = linksBox;
    if (box == null) return 'Settlements are not available on this device.';
    if (reason.trim().isEmpty) return 'Enter a reason.';
    for (final l in box.values) {
      if (l.id == id && l.kind == ReceiptLink.kindWriteoff) {
        if (l.voidedAt != null) return 'This settlement is already voided.';
        l.voidedAt = DateTime.now();
        l.voidReason = reason.trim();
        await l.save();
        return null;
      }
    }
    return 'Settlement not found.';
  }
}
