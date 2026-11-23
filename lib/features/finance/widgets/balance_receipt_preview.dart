import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/business_settings.dart';
import '../../../models/receipt.dart';
import '../balance_receipt_view.dart';

/// On-screen preview of a balance receipt, styled to match the sale receipt
/// preview (same width, fonts, colours and labels). A balance receipt has no
/// item lines, so the sale preview widget is not used for these.
class BalanceReceiptPreview extends StatelessWidget {
  final Receipt receipt;
  final BusinessSettings business;

  const BalanceReceiptPreview({
    super.key,
    required this.receipt,
    required this.business,
  });

  @override
  Widget build(BuildContext context) {
    final view = BalanceReceiptView.fromReceipt(
      receipt,
      businessName: business.businessName,
      currency: business.currencySymbol,
      footnote: business.footnote,
    );
    final dateFormat = DateFormat('yyyy-MM-dd  HH:mm');

    return Container(
      width: 360,
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            business.businessName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          if (business.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              business.address,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
          const SizedBox(height: 10),
          const Divider(color: Colors.black26),
          const Text(
            'BALANCE PAYMENT',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const Divider(color: Colors.black26),
          Text(
            'Date: ${dateFormat.format(view.issuedAt)}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          Text(
            'Receipt Code: ${view.code}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          Text(
            'Original Receipt: ${view.originalCode}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          Text(
            'Cashier: ${view.cashierName}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          if (view.customerName.isNotEmpty)
            Text(
              'Customer: ${view.customerName}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          if (receipt.customerWhatsapp.isNotEmpty)
            Text(
              'Customer WA: ${receipt.customerWhatsapp}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          const SizedBox(height: 8),
          const Divider(color: Colors.black26),
          _totalsLine('Previous Balance', view.money(view.previousMinor)),
          _totalsLine('PAID NOW', view.money(view.paidMinor), bold: true),
          const Divider(color: Colors.black45),
          _totalsLine(
            'REMAINING BALANCE',
            view.money(view.remainingMinor),
            bold: true,
            highlight: !view.settled,
          ),
          if (view.settled)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Fully paid',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            'Payment: ${view.paymentMethod}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          if (view.footnote.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.black26),
            Text(
              view.footnote,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.black54,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _totalsLine(
    String label,
    String value, {
    bool bold = false,
    bool highlight = false,
  }) {
    final style = TextStyle(
      fontSize: bold ? 14 : 12,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: highlight ? Colors.red.shade800 : Colors.black87,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}