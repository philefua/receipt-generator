/// Pure rules for "Settle with adjustment" (handoff 5.6). No Hive, no Flutter.
///
/// A write-off closes a small leftover balance without any cash moving. It
/// lowers what the sale still owes, so Receivables stops showing it, and
/// reports show it as a deduction from revenue.
class WriteoffMath {
  WriteoffMath._();

  /// Plain-English problem with a proposed write-off, or null if it is fine.
  static String? validate({
    required bool isSale,
    required int outstandingMinor,
    required int amountMinor,
    required String reason,
  }) {
    if (!isSale) {
      return 'Only a sale receipt can be settled, not a balance receipt.';
    }
    if (outstandingMinor <= 0) return 'This receipt has no balance left.';
    if (amountMinor <= 0) return 'Enter an amount above zero.';
    if (amountMinor > outstandingMinor) {
      return 'The amount cannot be more than the balance owed.';
    }
    if (reason.trim().isEmpty) return 'Enter a reason.';
    return null;
  }
}
