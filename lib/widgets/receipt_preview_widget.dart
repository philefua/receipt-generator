import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/business_settings.dart';
import '../models/receipt.dart';

/// Visual, on-screen representation of a finalized receipt. Wrapped by the
/// caller in a RepaintBoundary when a screenshot capture (for WhatsApp
/// sharing) is required.
class ReceiptPreviewWidget extends StatelessWidget {
  final Receipt receipt;
  final BusinessSettings business;

  const ReceiptPreviewWidget({
    super.key,
    required this.receipt,
    required this.business,
  });

  @override
  Widget build(BuildContext context) {
    final currency = business.currencySymbol;
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
          Text(
            'Date: ${dateFormat.format(receipt.issuedAt)}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          Text(
            'Receipt Code: ${receipt.receiptCode}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          Text(
            'Cashier: ${receipt.cashierName}',
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
          if (receipt.customerName.isNotEmpty)
            Text(
              'Customer: ${receipt.customerName}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          if (receipt.customerWhatsapp.isNotEmpty)
            Text(
              'Customer WA: ${receipt.customerWhatsapp}',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          const SizedBox(height: 8),
          const Divider(color: Colors.black26),
         const Row(
            children: [
              Expanded(
                flex: 5,
                child: Text(
                  'ITEM',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'QTY',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'TOTAL',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
          const Divider(color: Colors.black26),
          ...receipt.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      item.name,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${item.quantity}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      '$currency${item.lineTotal.toStringAsFixed(2)}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: Colors.black26),
          _totalsLine('Subtotal', receipt.subtotal, currency),
          _totalsLine(
            'Discount (${receipt.discountPercent.toStringAsFixed(1)}%)',
            -receipt.discountAmount,
            currency,
          ),
          if (receipt.couponReference.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Coupon: ${receipt.couponReference}',
                style: const TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.black54,
                ),
              ),
            ),
          const Divider(color: Colors.black45),
          _totalsLine(
            'TOTAL PAYABLE',
            receipt.totalPayable,
            currency,
            bold: true,
          ),
          if (receipt.balanceOwed > 0) ...[
            _totalsLine('Deposit Paid', receipt.depositPaid, currency),
            _totalsLine(
              'BALANCE OWED',
              receipt.balanceOwed,
              currency,
              bold: true,
              highlight: true,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Payment: ${receipt.paymentMethod}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          if (business.footnote.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(color: Colors.black26),
            Text(
              business.footnote,
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
    double value,
    String currency, {
    bool bold = false,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: bold ? 14 : 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: highlight ? Colors.red.shade800 : Colors.black87,
            ),
          ),
          Text(
            '$currency${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: bold ? 14 : 12,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: highlight ? Colors.red.shade800 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}