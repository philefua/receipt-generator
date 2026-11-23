/// Pure balance arithmetic for linked balance payments (handoff section 5).
/// No Hive and no Flutter, so it is trivial to test. All sums use integer
/// minor units (amount x 100) so totals never drift.
///
///   outstanding = original total - original deposit - sum(linked payments)
///
/// Outstanding is computed every time and never stored, and it is never
/// negative.
class SaleSummary {
  final String code;
  final int totalMinor;
  final int depositMinor;

  const SaleSummary({
    required this.code,
    required this.totalMinor,
    required this.depositMinor,
  });
}

class PaymentSummary {
  /// Code of the original sale this payment was made against.
  final String linkedCode;
  final int amountMinor;

  const PaymentSummary({required this.linkedCode, required this.amountMinor});
}

class BalanceMath {
  BalanceMath._();

  static int toMinor(double v) => (v * 100).round();

  static double fromMinor(int minor) => minor / 100;

  /// Never below zero, even if old data over-paid.
  static int outstandingMinor({
    required int totalMinor,
    required int depositMinor,
    required int paidLaterMinor,
  }) {
    final value = totalMinor - depositMinor - paidLaterMinor;
    return value < 0 ? 0 : value;
  }

  /// Sum of balance payments per original sale code.
  static Map<String, int> paidLaterByCode(Iterable<PaymentSummary> payments) {
    final map = <String, int>{};
    for (final p in payments) {
      map[p.linkedCode] = (map[p.linkedCode] ?? 0) + p.amountMinor;
    }
    return map;
  }

  /// Outstanding balance for every sale. Payments that point at an unknown
  /// code are ignored here (phase 6 surfaces them as unmatched).
  static Map<String, int> outstandingBySale(
    Iterable<SaleSummary> sales,
    Iterable<PaymentSummary> payments,
  ) {
    final paid = paidLaterByCode(payments);
    return {
      for (final s in sales)
        s.code: outstandingMinor(
          totalMinor: s.totalMinor,
          depositMinor: s.depositMinor,
          paidLaterMinor: paid[s.code] ?? 0,
        ),
    };
  }

  /// Returns a plain-English problem with the payment, or null if it is fine.
  static String? validatePayment({
    required bool originalIsSale,
    required int outstandingMinor,
    required int amountMinor,
  }) {
    if (!originalIsSale) {
      return 'That is a balance receipt. Enter the number of the original sale receipt.';
    }
    if (outstandingMinor <= 0) {
      return 'This receipt has no balance left to pay.';
    }
    if (amountMinor <= 0) return 'Enter an amount above zero.';
    if (amountMinor > outstandingMinor) {
      return 'The amount cannot be more than the balance owed.';
    }
    return null;
  }
}
