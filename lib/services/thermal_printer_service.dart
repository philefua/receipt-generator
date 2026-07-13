import 'dart:async';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../models/business_settings.dart';
import '../models/receipt.dart';

/// Represents a discoverable/paired Bluetooth printer.
class PrinterDevice {
  final String name;
  final String address;

  const PrinterDevice({required this.name, required this.address});

  @override
  String toString() => '$name ($address)';
}

/// Result wrapper for printer operations, since print_bluetooth_thermal
/// APIs return plain booleans/strings rather than throwing.
class PrinterOperationResult {
  final bool success;
  final String message;

  const PrinterOperationResult({required this.success, required this.message});

  factory PrinterOperationResult.ok([String message = 'OK']) =>
      PrinterOperationResult(success: true, message: message);

  factory PrinterOperationResult.fail(String message) =>
      PrinterOperationResult(success: false, message: message);
}

/// Handles Bluetooth discovery/connection and ESC/POS document generation
/// for 58mm thermal receipt printers.
class ThermalPrinterService {
  ThermalPrinterService._internal();

  static final ThermalPrinterService instance =
      ThermalPrinterService._internal();

  static const int _paperWidthChars = 32; // standard 58mm @ Font A (12x24)

  String? _connectedAddress;

  bool get isConnected => _connectedAddress != null;

  String? get connectedAddress => _connectedAddress;

  // -----------------------------------------------------------------------
  // 1. Bluetooth Scanner & Connector
  // -----------------------------------------------------------------------

  /// Returns the list of devices already paired with the Android OS.
  /// print_bluetooth_thermal relies on OS-level pairing rather than raw
  /// BLE scanning, so the printer must be paired via system Bluetooth
  /// settings first.
  Future<List<PrinterDevice>> getPairedDevices() async {
    try {
      final List<BluetoothInfo> devices =
          await PrintBluetoothThermal.pairedBluetooths;
      return devices
          .map((d) => PrinterDevice(name: d.name, address: d.macAdress))
          .toList(growable: false);
    } catch (e) {
      return const [];
    }
  }

  /// Connects to a printer at the given MAC address. Disconnects any
  /// previously connected printer first to avoid dangling sockets.
  Future<PrinterOperationResult> connect(String address) async {
    try {
      if (_connectedAddress != null && _connectedAddress != address) {
        await disconnect();
      }

      final bool alreadyConnected =
          await PrintBluetoothThermal.connectionStatus;
      if (alreadyConnected && _connectedAddress == address) {
        return PrinterOperationResult.ok('Already connected.');
      }

      final bool result = await PrintBluetoothThermal.connect(
        macPrinterAddress: address,
      );

      if (result) {
        _connectedAddress = address;
        return PrinterOperationResult.ok('Connected to $address');
      }
      return PrinterOperationResult.fail(
        'Failed to connect to printer at $address',
      );
    } catch (e) {
      return PrinterOperationResult.fail('Connection error: $e');
    }
  }

  Future<PrinterOperationResult> disconnect() async {
    try {
      final bool result = await PrintBluetoothThermal.disconnect;
      _connectedAddress = null;
      return result
          ? PrinterOperationResult.ok('Disconnected.')
          : PrinterOperationResult.fail('Disconnect returned false.');
    } catch (e) {
      return PrinterOperationResult.fail('Disconnect error: $e');
    }
  }

  Future<bool> checkConnectionStatus() async {
    try {
      final status = await PrintBluetoothThermal.connectionStatus;
      if (!status) {
        _connectedAddress = null;
      }
      return status;
    } catch (e) {
      _connectedAddress = null;
      return false;
    }
  }

  // -----------------------------------------------------------------------
  // 2 & 3. Document Formatting Engine (58mm, bold heading, wrapped text,
  // aligned columns)
  // -----------------------------------------------------------------------

  /// Builds the full ESC/POS byte payload for a finalized [Receipt].
  Future<List<int>> buildReceiptBytes({
    required Receipt receipt,
    required BusinessSettings business,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    final List<int> bytes = [];

    // --- Header: business name, bold, centered ---
    bytes += generator.text(
      business.businessName,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );

    if (business.address.isNotEmpty) {
      bytes += generator.text(
        business.address,
        styles: const PosStyles(align: PosAlign.center),
      );
    }

    final contactLine = [
      if (business.phone.isNotEmpty) business.phone,
      if (business.whatsapp.isNotEmpty) 'WA: ${business.whatsapp}',
    ].join(' | ');
    if (contactLine.isNotEmpty) {
      bytes += generator.text(
        contactLine,
        styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
      );
    }

    final socialLine = [
      if (business.website.isNotEmpty) business.website,
      if (business.instagram.isNotEmpty) 'IG: ${business.instagram}',
      if (business.facebook.isNotEmpty) 'FB: ${business.facebook}',
    ].join(' | ');
    if (socialLine.isNotEmpty) {
      bytes += generator.text(
        socialLine,
        styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
      );
    }

    bytes += generator.hr(ch: '-');

    // --- Meta: timestamp, discount/serial code, customer, payment ---
    bytes += generator.text(
      'Date: ${_formatDateTime(receipt.issuedAt)}',
      styles: const PosStyles(align: PosAlign.left),
    );
    bytes += generator.text(
      'Code: ${receipt.receiptCode}',
      styles: const PosStyles(align: PosAlign.left, bold: true),
    );
    bytes += generator.text(
      'Cashier: ${receipt.cashierName}',
      styles: const PosStyles(align: PosAlign.left),
    );

    if (receipt.customerName.isNotEmpty) {
      bytes += generator.text(
        'Customer: ${receipt.customerName}',
        styles: const PosStyles(align: PosAlign.left),
      );
    }
    if (receipt.customerWhatsapp.isNotEmpty) {
      bytes += generator.text(
        'Customer WA: ${receipt.customerWhatsapp}',
        styles: const PosStyles(align: PosAlign.left),
      );
    }

    bytes += generator.hr(ch: '-');

    // --- Column header: Item | Qty | Total ---
    bytes += generator.text(
      _buildColumnRow('ITEM', 'QTY', 'TOTAL'),
      styles: const PosStyles(bold: true),
    );
    bytes += generator.hr(ch: '-');

    // --- Itemized lines, wrapped and column-aligned ---
    for (final item in receipt.items) {
      bytes += _emitItemRow(
        generator: generator,
        name: item.name,
        unitPrice: item.unitPrice,
        quantity: item.quantity,
        lineTotal: item.lineTotal,
      );
    }

    bytes += generator.hr(ch: '-');

    // --- Totals block ---
    bytes += generator.text(_buildTotalsRow('Subtotal', receipt.subtotal));
    bytes += generator.text(
      _buildTotalsRow(
        'Discount (${receipt.discountPercent.toStringAsFixed(1)}%)',
        -receipt.discountAmount,
      ),
    );
    bytes += generator.hr(ch: '=');
    bytes += generator.text(
      _buildTotalsRow('TOTAL', receipt.totalPayable),
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    );
    bytes += generator.text(
      'Payment: ${receipt.paymentMethod}',
      styles: const PosStyles(align: PosAlign.left, bold: true),
    );

    // --- Footer ---
    if (business.footnote.isNotEmpty) {
      bytes += generator.hr(ch: '-');
      bytes += generator.text(
        business.footnote,
        styles: const PosStyles(align: PosAlign.center),
      );
    }

    bytes += generator.feed(2);
    bytes += generator.cut();

    return bytes;
  }

  /// Emits one or more printer lines for a single item, wrapping the
  /// description across multiple lines when it doesn't fit alongside
  /// the Qty/Total columns, and printing Qty/Total only on the first line.
  List<int> _emitItemRow({
    required Generator generator,
    required String name,
    required double unitPrice,
    required int quantity,
    required double lineTotal,
  }) {
    const int qtyWidth = 4;
    const int totalWidth = 9;
    final int nameWidth = _paperWidthChars - qtyWidth - totalWidth;

    final List<String> wrappedNameLines = _wrapText(name, nameWidth);
    final String qtyStr = quantity.toString().padLeft(qtyWidth - 1);
    final String totalStr = lineTotal.toStringAsFixed(2).padLeft(totalWidth - 1);

    final List<int> out = [];

    for (int i = 0; i < wrappedNameLines.length; i++) {
      final String namePart = wrappedNameLines[i].padRight(nameWidth);
      final bool isFirstLine = i == 0;

      final String row = isFirstLine
          ? '$namePart$qtyStr $totalStr'
          : '$namePart${' ' * qtyWidth}${' ' * totalWidth}';

      out.addAll(generator.text(row, styles: const PosStyles(align: PosAlign.left)));
    }

    // Unit price sub-line for clarity when quantity > 1.
    if (quantity > 1) {
      out.addAll(
        generator.text(
          '  @ ${unitPrice.toStringAsFixed(2)} each',
          styles: const PosStyles(
            align: PosAlign.left,
            fontType: PosFontType.fontB,
          ),
        ),
      );
    }

    return out;
  }

  /// Greedy word-wrap that never splits a word mid-character unless the
  /// single word itself exceeds the column width.
  List<String> _wrapText(String text, int width) {
    if (text.isEmpty) return [''];
    final words = text.split(RegExp(r'\s+'));
    final List<String> lines = [];
    StringBuffer current = StringBuffer();

    for (final word in words) {
      if (word.length > width) {
        if (current.isNotEmpty) {
          lines.add(current.toString());
          current = StringBuffer();
        }
        for (int i = 0; i < word.length; i += width) {
          final end = (i + width < word.length) ? i + width : word.length;
          lines.add(word.substring(i, end));
        }
        continue;
      }

      final prospective =
          current.isEmpty ? word : '${current.toString()} $word';
      if (prospective.length > width) {
        lines.add(current.toString());
        current = StringBuffer(word);
      } else {
        current
          ..clear()
          ..write(prospective);
      }
    }

    if (current.isNotEmpty) {
      lines.add(current.toString());
    }

    return lines.isEmpty ? [''] : lines;
  }

  String _buildColumnRow(String item, String qty, String total) {
    const int qtyWidth = 4;
    const int totalWidth = 9;
    final int nameWidth = _paperWidthChars - qtyWidth - totalWidth;
    return item.padRight(nameWidth) +
        qty.padLeft(qtyWidth - 1) +
        ' ' +
        total.padLeft(totalWidth - 1);
  }

  String _buildTotalsRow(String label, double value) {
    final String valueStr = value.toStringAsFixed(2);
    final int spaceCount = _paperWidthChars - label.length - valueStr.length;
    final String spacer = spaceCount > 0 ? ' ' * spaceCount : ' ';
    return '$label$spacer$valueStr';
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  // -----------------------------------------------------------------------
  // 4. Execute Printing
  // -----------------------------------------------------------------------

  /// Streams the given byte payload to the currently connected printer.
  /// Returns a [PrinterOperationResult] rather than throwing, so calling
  /// UI code can surface a clean success/failure message.
  Future<PrinterOperationResult> printBytes(List<int> bytes) async {
    try {
      final bool connected = await checkConnectionStatus();
      if (!connected) {
        return PrinterOperationResult.fail(
          'No printer connected. Connect to a device first.',
        );
      }

      final Uint8List payload = Uint8List.fromList(bytes);
      final bool result = await PrintBluetoothThermal.writeBytes(payload);

      return result
          ? PrinterOperationResult.ok('Receipt sent to printer.')
          : PrinterOperationResult.fail('Printer rejected the print job.');
    } catch (e) {
      return PrinterOperationResult.fail('Print error: $e');
    }
  }

  /// Convenience method: builds and prints a receipt in one call.
  Future<PrinterOperationResult> printReceipt({
    required Receipt receipt,
    required BusinessSettings business,
  }) async {
    try {
      final bytes = await buildReceiptBytes(receipt: receipt, business: business);
      return printBytes(bytes);
    } catch (e) {
      return PrinterOperationResult.fail('Failed to build receipt: $e');
    }
  }
}