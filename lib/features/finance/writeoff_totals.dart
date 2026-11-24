import 'package:hive/hive.dart';

import 'balance_math.dart';
import 'finance_boxes.dart';
import 'models/receipt_link.dart';

/// Reads the active (not voided) write-offs from the receipt_links box.
///
/// Kept separate so both the balance maths and the legacy matcher can use it
/// without importing each other. Never throws: if the box is unavailable the
/// result is simply "no write-offs".
class WriteoffTotals {
  WriteoffTotals._();

  /// Total written off per receipt code, in minor units.
  static Map<String, int> read() {
    try {
      if (!Hive.isBoxOpen(FinanceBoxes.receiptLinksBox)) return const {};
      final box = Hive.box<ReceiptLink>(FinanceBoxes.receiptLinksBox);
      final map = <String, int>{};
      for (final l in box.values) {
        if (l.kind == ReceiptLink.kindWriteoff && l.voidedAt == null) {
          map[l.receiptCode] =
              (map[l.receiptCode] ?? 0) + BalanceMath.toMinor(l.amount);
        }
      }
      return map;
    } catch (_) {
      return const {};
    }
  }
}
