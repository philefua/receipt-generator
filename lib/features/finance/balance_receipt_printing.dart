import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

import '../../models/business_settings.dart';
import '../../models/receipt.dart';
import 'balance_receipt_view.dart';

const int _paperWidthChars = 32;

String _totalsRow(String label, String value) {
  final spaceCount = _paperWidthChars - label.length - value.length;
  final spacer = spaceCount > 0 ? ' ' * spaceCount : ' ';
  return '$label$spacer$value';
}

String _formatDateTime(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}

/// ESC/POS bytes for a balance receipt on a 58mm printer. Same header and
/// footer as the sale receipt; the body shows BALANCE PAYMENT, the original
/// receipt number, previous balance, amount paid now and remaining balance.
/// The sale receipt template is not touched.
Future<List<int>> buildBalanceReceiptBytes({
  required Receipt receipt,
  required BusinessSettings business,
}) async {
  final view = BalanceReceiptView.fromReceipt(
    receipt,
    businessName: business.businessName,
    currency: business.currencySymbol,
    footnote: business.footnote,
  );

  final profile = await CapabilityProfile.load();
  final generator = Generator(PaperSize.mm58, profile);
  final List<int> bytes = <int>[];

  bytes.addAll(generator.text(
    business.businessName,
    styles: const PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    ),
  ));

  if (business.address.isNotEmpty) {
    bytes.addAll(generator.text(
      business.address,
      styles: const PosStyles(align: PosAlign.center),
    ));
  }

  final contactLine = [
    if (business.phone.isNotEmpty) business.phone,
    if (business.whatsapp.isNotEmpty) 'WA: ${business.whatsapp}',
  ].join(' | ');
  if (contactLine.isNotEmpty) {
    bytes.addAll(generator.text(
      contactLine,
      styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
    ));
  }

  bytes.addAll(generator.hr(ch: '-'));

  bytes.addAll(generator.text(
    'BALANCE PAYMENT',
    styles: const PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
    ),
  ));

  bytes.addAll(generator.hr(ch: '-'));

  bytes.addAll(generator.text(
    'Date: ${_formatDateTime(view.issuedAt)}',
    styles: const PosStyles(align: PosAlign.left),
  ));
  bytes.addAll(generator.text(
    'Code: ${view.code}',
    styles: const PosStyles(align: PosAlign.left, bold: true),
  ));
  bytes.addAll(generator.text(
    'Original Receipt: ${view.originalCode}',
    styles: const PosStyles(align: PosAlign.left, bold: true),
  ));
  bytes.addAll(generator.text(
    'Cashier: ${view.cashierName}',
    styles: const PosStyles(align: PosAlign.left),
  ));
  if (view.customerName.isNotEmpty) {
    bytes.addAll(generator.text(
      'Customer: ${view.customerName}',
      styles: const PosStyles(align: PosAlign.left),
    ));
  }

  bytes.addAll(generator.hr(ch: '-'));

  bytes.addAll(generator.text(
    _totalsRow('Previous Balance', view.money(view.previousMinor)),
  ));
  bytes.addAll(generator.text(
    _totalsRow('PAID NOW', view.money(view.paidMinor)),
    styles: const PosStyles(
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size1,
    ),
  ));
  bytes.addAll(generator.hr(ch: '='));
  bytes.addAll(generator.text(
    _totalsRow('REMAINING', view.money(view.remainingMinor)),
    styles: const PosStyles(bold: true),
  ));
  if (view.settled) {
    bytes.addAll(generator.text(
      'Fully paid',
      styles: const PosStyles(align: PosAlign.center, bold: true),
    ));
  }

  bytes.addAll(generator.text(
    'Payment: ${view.paymentMethod}',
    styles: const PosStyles(align: PosAlign.left, bold: true),
  ));

  if (business.footnote.isNotEmpty) {
    bytes.addAll(generator.hr(ch: '-'));
    bytes.addAll(generator.text(
      business.footnote,
      styles: const PosStyles(align: PosAlign.center),
    ));
  }

  bytes.addAll(generator.feed(2));
  bytes.addAll(generator.cut());

  return bytes;
}
