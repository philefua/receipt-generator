import '../../models/receipt.dart';
import 'balance_math.dart';

/// Everything a balance receipt shows, taken from the saved receipt itself so
/// a reprint years later is identical. A balance receipt stores:
///   totalPayable / depositPaid = amount paid now
///   balanceOwed                = balance remaining after this payment
///   linkedReceiptId            = the original sale's receipt number
/// Previous balance is amount paid + remaining.
///
/// The print, preview and WhatsApp text all read this one class, so the three
/// can never disagree.
class BalanceReceiptView {
  final String businessName;
  final String currency;
  final String footnote;
  final String code;
  final String originalCode;
  final String customerName;
  final String paymentMethod;
  final String cashierName;
  final DateTime issuedAt;
  final int previousMinor;
  final int paidMinor;
  final int remainingMinor;

  const BalanceReceiptView({
    required this.businessName,
    required this.currency,
    required this.footnote,
    required this.code,
    required this.originalCode,
    required this.customerName,
    required this.paymentMethod,
    required this.cashierName,
    required this.issuedAt,
    required this.previousMinor,
    required this.paidMinor,
    required this.remainingMinor,
  });

  factory BalanceReceiptView.fromReceipt(
    Receipt receipt, {
    required String businessName,
    required String currency,
    String footnote = '',
  }) {
    final paid = BalanceMath.toMinor(receipt.totalPayable);
    final remaining = BalanceMath.toMinor(receipt.balanceOwed);
    return BalanceReceiptView(
      businessName: businessName,
      currency: currency,
      footnote: footnote.trim(),
      code: receipt.receiptCode,
      originalCode: receipt.linkedReceiptId ?? '',
      customerName: receipt.customerName,
      paymentMethod: receipt.paymentMethod,
      cashierName: receipt.cashierName,
      issuedAt: receipt.issuedAt,
      previousMinor: paid + remaining,
      paidMinor: paid,
      remainingMinor: remaining,
    );
  }

  bool get settled => remainingMinor == 0;

  String money(int minor) => '$currency${BalanceMath.fromMinor(minor).toStringAsFixed(2)}';

  /// Customer-facing WhatsApp text. Same tone as the sale receipt message.
  String whatsappMessage() {
    final b = StringBuffer();
    b.writeln(businessName);
    b.writeln();
    b.writeln('BALANCE PAYMENT');
    b.writeln('Receipt No: $code');
    b.writeln('Original Receipt: $originalCode');
    b.writeln();
    b.writeln('Previous Balance: ${money(previousMinor)}');
    b.writeln('Amount Paid Now: ${money(paidMinor)}');
    b.writeln('Remaining Balance: ${money(remainingMinor)}');
    if (settled) {
      b.writeln();
      b.writeln('Fully paid.');
    }
    b.writeln();
    b.writeln('Thank you for your patronage!');
    if (footnote.isNotEmpty) {
      b.writeln();
      b.writeln(footnote);
    }
    return b.toString();
  }
}

/// Second line of a history entry. For an ordinary sale with nothing owed it
/// is exactly the text the history page always showed.
String historySubtitle({
  required Receipt receipt,
  required String dateText,
  required String currency,
  required Map<String, int> outstandingByCode,
}) {
  final customer =
      receipt.customerName.isNotEmpty ? receipt.customerName : 'Walk-in customer';

  if (receipt.receiptType == Receipt.typeBalancePayment) {
    return 'Balance payment for ${receipt.linkedReceiptId ?? '?'} • $customer\n'
        '$dateText • ${receipt.paymentMethod}';
  }

  var line2 = '$dateText • ${receipt.paymentMethod}';
  // Only sales that were opened with a balance get a status.
  if (BalanceMath.toMinor(receipt.totalPayable) >
      BalanceMath.toMinor(receipt.depositPaid)) {
    final outstanding = outstandingByCode[receipt.receiptCode] ?? 0;
    line2 += outstanding > 0
        ? ' • Balance $currency${BalanceMath.fromMinor(outstanding).toStringAsFixed(2)}'
        : ' • Settled';
  }
  return '$customer\n$line2';
}
