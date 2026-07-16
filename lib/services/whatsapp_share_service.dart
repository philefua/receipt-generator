import 'package:url_launcher/url_launcher.dart';

import '../models/business_settings.dart';
import '../models/receipt.dart';

/// Result wrapper for share operations so calling UI code can display a
/// clean success/failure message without needing try/catch everywhere.
class ShareOperationResult {
  final bool success;
  final String message;

  const ShareOperationResult({required this.success, required this.message});

  factory ShareOperationResult.ok([String message = 'Shared successfully.']) =>
      ShareOperationResult(success: true, message: message);

  factory ShareOperationResult.fail(String message) =>
      ShareOperationResult(success: false, message: message);
}

/// Sends a formatted, multi-line summary of a finalized receipt directly
/// to the customer's WhatsApp chat via the wa.me deep link. This avoids
/// on-device image rendering entirely, relying only on a plain pre-filled
/// text message — the most reliable sharing path available across devices.
class WhatsappShareService {
  WhatsappShareService._internal();

  static final WhatsappShareService instance =
      WhatsappShareService._internal();

  /// Opens WhatsApp directly on the specified customer's chat thread with
  /// a pre-filled text message.
  Future<ShareOperationResult> openWhatsAppChat({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final String sanitized = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
      if (sanitized.isEmpty) {
        return ShareOperationResult.fail('Invalid WhatsApp phone number.');
      }

      final Uri uri = Uri.parse(
        'https://wa.me/$sanitized?text=${Uri.encodeComponent(message)}',
      );

      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      return launched
          ? ShareOperationResult.ok('WhatsApp chat opened.')
          : ShareOperationResult.fail(
              'Could not open WhatsApp. Is it installed?',
            );
    } catch (e) {
      return ShareOperationResult.fail('Failed to open WhatsApp chat: $e');
    }
  }

  /// Builds a multi-line, customer-facing summary of the receipt. The
  /// business name appears as a header, and the manager's configured
  /// footnote (if set) appears at the very end. Address and phone are
  /// deliberately excluded — only the business name, transaction details,
  /// and footnote are included.
  String _buildReceiptMessage(Receipt receipt, BusinessSettings business) {
    final buffer = StringBuffer();
    final currencySymbol = business.currencySymbol;

    buffer.writeln(business.businessName);
    buffer.writeln();
    buffer.writeln('Receipt No: ${receipt.receiptCode}');
    buffer.writeln();
    buffer.writeln('Items:');
    for (final item in receipt.items) {
      buffer.writeln(
        '- ${item.name} x${item.quantity} — $currencySymbol${item.lineTotal.toStringAsFixed(2)}',
      );
    }
    buffer.writeln();
    buffer.writeln(
      'Subtotal: $currencySymbol${receipt.subtotal.toStringAsFixed(2)}',
    );

    if (receipt.discountPercent > 0) {
      buffer.writeln(
        'Discount (${receipt.discountPercent.toStringAsFixed(1)}%): '
        '-$currencySymbol${receipt.discountAmount.toStringAsFixed(2)}',
      );
    }

    buffer.writeln(
      'Total Payable: $currencySymbol${receipt.totalPayable.toStringAsFixed(2)}',
    );

    if (receipt.balanceOwed > 0) {
      buffer.writeln(
        'Deposit Paid: $currencySymbol${receipt.depositPaid.toStringAsFixed(2)}',
      );
      buffer.writeln(
        'Balance Owed: $currencySymbol${receipt.balanceOwed.toStringAsFixed(2)}',
      );
    }

    buffer.writeln();
    buffer.writeln('Thank you for your patronage!');

    if (business.footnote.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln(business.footnote.trim());
    }

    return buffer.toString();
  }

  /// Sends the formatted receipt summary directly to the customer's
  /// WhatsApp chat.
  Future<ShareOperationResult> shareReceiptDetailsToCustomer({
    required Receipt receipt,
    required BusinessSettings business,
  }) async {
    final message = _buildReceiptMessage(receipt, business);
    return openWhatsAppChat(
      phoneNumber: receipt.customerWhatsapp,
      message: message,
    );
  }
}