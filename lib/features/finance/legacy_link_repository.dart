import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../models/receipt.dart';
import 'balance_math.dart';
import 'finance_boxes.dart';
import 'legacy_balance_resolver.dart';
import 'models/receipt_link.dart';

/// Connects the pure [LegacyBalanceResolver] to Hive.
///
/// Reads receipts (never writes them) and reads/writes only the
/// receipt_links box. Nothing here edits or deletes a receipt.
/// What linked legacy balance receipts change in the balance maths.
class LegacyAdjustments {
  /// Payments to add to the phase 5 payments, per original sale.
  final List<PaymentSummary> payments;

  /// Every linked legacy balance receipt (not a valid "original sale").
  final Set<String> linkedCodes;

  /// Linked legacy receipts whose own "owed" figure must count as zero.
  final Set<String> clearedOwn;

  const LegacyAdjustments({
    this.payments = const [],
    this.linkedCodes = const {},
    this.clearedOwn = const {},
  });

  static const LegacyAdjustments none = LegacyAdjustments();
}

class LegacyLinkRepository {
  LegacyLinkRepository._();
  static final LegacyLinkRepository instance = LegacyLinkRepository._();

  /// Same box the app already uses for receipts (see AppStateController).
  static const String _receiptsBoxName = 'receipts_box';

  Box<Receipt>? get receiptsBox {
    try {
      return Hive.isBoxOpen(_receiptsBoxName)
          ? Hive.box<Receipt>(_receiptsBoxName)
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

  List<LegacyReceiptRecord> records() {
    final box = receiptsBox;
    if (box == null) return const [];
    return _recordsFrom(box.values);
  }

  static List<LegacyReceiptRecord> _recordsFrom(Iterable<Receipt> all) {
    return [
      for (final r in all)
        LegacyReceiptRecord(
          code: r.receiptCode,
          issuedAt: r.issuedAt,
          isBalanceType: r.isBalancePayment,
          linkedCode: r.linkedReceiptId,
          customerName: r.customerName,
          customerWhatsapp: r.customerWhatsapp,
          itemNames: [for (final i in r.items) i.name],
          couponReference: r.couponReference,
          totalMinor: BalanceMath.toMinor(r.totalPayable),
          depositMinor: BalanceMath.toMinor(r.depositPaid),
        ),
    ];
  }

  /// Active manual links, oldest first so the latest one for a receipt wins.
  List<ReceiptLink> _activeLinks() {
    final box = linksBox;
    if (box == null) return const [];
    return [
      for (final l in box.values)
        if (l.kind == ReceiptLink.kindLink && l.voidedAt == null) l,
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  List<ManualLinkRecord> _manualRecords() => [
        for (final l in _activeLinks())
          ManualLinkRecord(
            id: l.id,
            receiptCode: l.receiptCode,
            originalCode: l.originalReceiptCode,
            appliedMinor: BalanceMath.toMinor(l.amount),
          ),
      ];

  LegacyResolution resolve() => LegacyBalanceResolver.resolve(
      receipts: records(), manualLinks: _manualRecords());

  /// What the balance maths must add for linked legacy receipts. Works on the
  /// receipts the caller already has. Never throws: if anything goes wrong the
  /// cashier simply gets the phase 5 numbers.
  LegacyAdjustments adjustmentsFor(Iterable<Receipt> all) {
    try {
      final resolution = LegacyBalanceResolver.resolve(
          receipts: _recordsFrom(all), manualLinks: _manualRecords());
      return LegacyAdjustments(
        payments: resolution.payments,
        linkedCodes: resolution.linkedCodes,
        clearedOwn: resolution.ownBalanceCleared,
      );
    } catch (_) {
      return LegacyAdjustments.none;
    }
  }

  /// For the hub card badge. Never throws.
  int needsReviewCount() {
    try {
      if (!isReady) return 0;
      return resolve().needsReviewCount;
    } catch (_) {
      return 0;
    }
  }

  /// The note saved with a manual link, for display.
  String? noteFor(String linkId) {
    final box = linksBox;
    if (box == null) return null;
    for (final l in box.values) {
      if (l.id == linkId && l.reason.trim().isNotEmpty) return l.reason;
    }
    return null;
  }

  /// Saves a manual link. Returns null on success, or a plain-English reason
  /// it was refused. A new link for the same receipt replaces the old one
  /// (the old one is voided, not deleted).
  Future<String?> saveManualLink({
    required String legacyCode,
    required String originalCode,
    required double amount,
    String note = '',
    DateTime? now,
  }) async {
    final box = linksBox;
    if (box == null || receiptsBox == null) {
      return 'Links are not available on this device.';
    }
    if (amount.isNaN || amount.isInfinite) return 'Enter a valid amount.';

    final problem = LegacyBalanceResolver.validateManualLink(
      receipts: records(),
      manualLinks: _manualRecords(),
      legacyCode: legacyCode,
      originalCode: originalCode,
      appliedMinor: BalanceMath.toMinor(amount),
    );
    if (problem != null) return problem;

    final clock = now ?? DateTime.now();
    final previous = [
      for (final l in _activeLinks())
        if (l.receiptCode == legacyCode.trim()) l,
    ];

    final link = ReceiptLink(
      id: const Uuid().v4(),
      kind: ReceiptLink.kindLink,
      receiptCode: legacyCode.trim(),
      originalReceiptCode: originalCode.trim(),
      amount: BalanceMath.fromMinor(BalanceMath.toMinor(amount)),
      reason: note.trim(),
      createdAt: clock,
    );
    await box.put(link.id, link);

    for (final old in previous) {
      old.voidedAt = clock;
      old.voidReason = 'Replaced by a new link';
      await old.save();
    }
    return null;
  }

  /// Voids a manual link. The record stays; the receipt goes back to the
  /// automatic result (linked again if clean, otherwise back on the list).
  Future<String?> voidLink(String linkId, String reason) async {
    final box = linksBox;
    if (box == null) return 'Links are not available on this device.';
    if (reason.trim().isEmpty) return 'Enter a reason.';
    for (final l in box.values) {
      if (l.id == linkId) {
        if (l.voidedAt != null) return 'This link is already voided.';
        l.voidedAt = DateTime.now();
        l.voidReason = reason.trim();
        await l.save();
        return null;
      }
    }
    return 'Link not found.';
  }
}
