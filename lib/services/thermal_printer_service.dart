import 'dart:async';
import 'dart:typed_data';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/business_settings.dart';
import '../models/receipt.dart';

/// Standard Serial Port Profile (SPP) UUID used by virtually all classic
/// Bluetooth thermal receipt printers, including Xprinter models.
const String _sppUuid = '00001101-0000-1000-8000-00805F9B34FB';

/// Represents a discoverable/paired Bluetooth printer.
class PrinterDevice {
  final String name;
  final String address;

  const PrinterDevice({required this.name, required this.address});

  @override
  String toString() => '$name ($address)';
}

/// Result wrapper for printer operations.
class PrinterOperationResult {
  final bool success;
  final String message;

  const PrinterOperationResult({required this.success, required this.message});

  factory PrinterOperationResult.ok([String message = 'OK']) =>
      PrinterOperationResult(success: true, message: message);

  factory PrinterOperationResult.fail(String message) =>
      PrinterOperationResult(success: false, message: message);
}

/// Handles Bluetooth Classic (RFCOMM/SPP) discovery/connection and ESC/POS
/// document generation for 58mm thermal receipt printers, using
/// flutter_classic_bluetooth for the transport layer.
class ThermalPrinterService {
  ThermalPrinterService._internal();

  static final ThermalPrinterService instance =
      ThermalPrinterService._internal();

  static const int _paperWidthChars = 32;

  final FlutterClassicBluetooth _bluetooth = FlutterClassicBluetooth();

  BtcConnection? _connection;
  String? _connectedAddress;
  String? _connectedName;

  bool get isConnected => _connection != null;

  String? get connectedAddress => _connectedAddress;

  String? get connectedName => _connectedName;

  /// Requests the runtime Bluetooth permissions required on Android 12+.
  Future<bool> requestPermissions() async {
    final statuses = await [
      Permission.bluetoothConnect,
      Permission.bluetooth,
    ].request();

    final bool allGranted = statuses.values.every(
      (status) => status.isGranted || status.isLimited,
    );

    if (allGranted) return true;

    final anyPermanentlyDenied = statuses.values.any(
      (status) => status.isPermanentlyDenied,
    );

    if (anyPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
  }

  Future<List<PrinterDevice>> getPairedDevices() async {
    final List<BtcDevice> devices = await _bluetooth.getPairedDevices();
    return devices
        .map((d) => PrinterDevice(name: d.displayName, address: d.address))
        .toList(growable: false);
  }

  /// Connects to the printer at [address] using Bluetooth Classic RFCOMM
  /// (SPP). Closes any existing connection first only if it's to a
  /// different address than the one being requested.
  Future<PrinterOperationResult> connect(
    String address, {
    String? name,
  }) async {
    try {
      if (_connection != null &&
          _connectedAddress != null &&
          _connectedAddress != address) {
        await disconnect();
      }

      if (_connection != null && _connectedAddress == address) {
        return PrinterOperationResult.ok('Already connected.');
      }

      final BtcConnection connection = await _bluetooth.connect(
        address: address,
        uuid: _sppUuid,
      );

      _connection = connection;
      _connectedAddress = address;
      _connectedName = name;

      // Brief settle delay after connecting, since some generic/clone
      // thermal printers report the connection as ready slightly before
      // they can actually accept a write.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      return PrinterOperationResult.ok('Connected to ${name ?? address}');
    } catch (e) {
      _connection = null;
      _connectedAddress = null;
      _connectedName = null;
      return PrinterOperationResult.fail(
        'Failed to connect to printer at ${name ?? address}: $e',
      );
    }
  }

  Future<PrinterOperationResult> disconnect() async {
    try {
      await _connection?.finish();
      _connection = null;
      _connectedAddress = null;
      _connectedName = null;
      return PrinterOperationResult.ok('Disconnected.');
    } catch (e) {
      _connection = null;
      _connectedAddress = null;
      _connectedName = null;
      return PrinterOperationResult.fail('Disconnect error: $e');
    }
  }

  Future<bool> checkConnectionStatus() async {
    return _connection != null;
  }

  Future<List<int>> buildReceiptBytes({
    required Receipt receipt,
    required BusinessSettings business,
  }) async {
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

    final socialLine = [
      if (business.website.isNotEmpty) business.website,
      if (business.instagram.isNotEmpty) 'IG: ${business.instagram}',
      if (business.facebook.isNotEmpty) 'FB: ${business.facebook}',
    ].join(' | ');
    if (socialLine.isNotEmpty) {
      bytes.addAll(generator.text(
        socialLine,
        styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB),
      ));
    }

    bytes.addAll(generator.hr(ch: '-'));

    bytes.addAll(generator.text(
      'Date: ${_formatDateTime(receipt.issuedAt)}',
      styles: const PosStyles(align: PosAlign.left),
    ));
    bytes.addAll(generator.text(
      'Code: ${receipt.receiptCode}',
      styles: const PosStyles(align: PosAlign.left, bold: true),
    ));
    bytes.addAll(generator.text(
      'Cashier: ${receipt.cashierName}',
      styles: const PosStyles(align: PosAlign.left),
    ));

    if (receipt.customerName.isNotEmpty) {
      bytes.addAll(generator.text(
        'Customer: ${receipt.customerName}',
        styles: const PosStyles(align: PosAlign.left),
      ));
    }
    if (receipt.customerWhatsapp.isNotEmpty) {
      bytes.addAll(generator.text(
        'Customer WA: ${receipt.customerWhatsapp}',
        styles: const PosStyles(align: PosAlign.left),
      ));
    }

    bytes.addAll(generator.hr(ch: '-'));

    bytes.addAll(generator.text(
      _buildColumnRow('ITEM', 'QTY', 'TOTAL'),
      styles: const PosStyles(bold: true),
    ));
    bytes.addAll(generator.hr(ch: '-'));

    for (final item in receipt.items) {
      bytes.addAll(_buildItemRowBytes(
        generator: generator,
        name: item.name,
        unitPrice: item.unitPrice,
        quantity: item.quantity,
        lineTotal: item.lineTotal,
      ));
    }

    bytes.addAll(generator.hr(ch: '-'));

    bytes.addAll(generator.text(_buildTotalsRow('Subtotal', receipt.subtotal)));
    bytes.addAll(generator.text(
      _buildTotalsRow(
        'Discount (${receipt.discountPercent.toStringAsFixed(1)}%)',
        -receipt.discountAmount,
      ),
    ));

    if (receipt.couponReference.isNotEmpty) {
      bytes.addAll(generator.text(
        'Coupon: ${receipt.couponReference}',
        styles: const PosStyles(align: PosAlign.left, fontType: PosFontType.fontB),
      ));
    }

    bytes.addAll(generator.hr(ch: '='));
    bytes.addAll(generator.text(
      _buildTotalsRow('TOTAL', receipt.totalPayable),
      styles: const PosStyles(
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size1,
      ),
    ));

    if (receipt.balanceOwed > 0) {
      bytes.addAll(generator.text(_buildTotalsRow('Deposit Paid', receipt.depositPaid)));
      bytes.addAll(generator.text(
        _buildTotalsRow('BALANCE OWED', receipt.balanceOwed),
        styles: const PosStyles(bold: true),
      ));
    }

    bytes.addAll(generator.text(
      'Payment: ${receipt.paymentMethod}',
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

  List<int> _buildItemRowBytes({
    required Generator generator,
    required String name,
    required double unitPrice,
    required int quantity,
    required double lineTotal,
  }) {
    const int qtyWidth = 4;
    const int totalWidth = 9;
    const int nameWidth = _paperWidthChars - qtyWidth - totalWidth;

    final List<String> wrappedNameLines = _wrapText(name, nameWidth);
    final String qtyStr = quantity.toString().padLeft(qtyWidth - 1);
    final String totalStr = lineTotal.toStringAsFixed(2).padLeft(totalWidth - 1);

    final List<int> out = <int>[];

    for (int i = 0; i < wrappedNameLines.length; i++) {
      final String namePart = wrappedNameLines[i].padRight(nameWidth);
      final bool isFirstLine = i == 0;

      final String row = isFirstLine
          ? '$namePart$qtyStr $totalStr'
          : '$namePart${' ' * qtyWidth}${' ' * totalWidth}';

      out.addAll(generator.text(row, styles: const PosStyles(align: PosAlign.left)));
    }

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
    const int nameWidth = _paperWidthChars - qtyWidth - totalWidth;
    final String namePart = item.padRight(nameWidth);
    final String qtyPart = qty.padLeft(qtyWidth - 1);
    final String totalPart = total.padLeft(totalWidth - 1);
    return '$namePart$qtyPart $totalPart';
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

  /// Sends [bytes] over the open RFCOMM connection.
  Future<PrinterOperationResult> printBytes(List<int> bytes) async {
    try {
      bool connected = await checkConnectionStatus();

      if (!connected && _connectedAddress != null) {
        final reconnectResult = await connect(
          _connectedAddress!,
          name: _connectedName,
        );
        connected = reconnectResult.success;
      }

      if (!connected || _connection == null) {
        return PrinterOperationResult.fail(
          'No printer connected. Connect to a device first.',
        );
      }

      final Uint8List payload = Uint8List.fromList(bytes);
      await _connection!.output.add(payload);

      return PrinterOperationResult.ok('Receipt sent to printer.');
    } catch (e) {
      return PrinterOperationResult.fail(
        'Printer rejected the print job: $e. Ensure it has paper and is powered on, then try again.',
      );
    }
  }

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