import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'models/business_settings.dart';
import 'models/license_state.dart';
import 'models/product_preset.dart';
import 'models/receipt.dart';
import 'pages/backend_page.dart';
import 'pages/frontend_page.dart';
import 'pages/license_lockout_page.dart';
import 'pages/printer_setup_page.dart';
import 'pages/receipt_history_page.dart';
import 'services/google_drive_service.dart';
import 'services/google_sheets_service.dart';
import 'services/license_service.dart';
import 'state/app_state_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  Hive.registerAdapter(BusinessSettingsAdapter());
  Hive.registerAdapter(ProductPresetAdapter());
  Hive.registerAdapter(ReceiptItemAdapter());
  Hive.registerAdapter(ReceiptAdapter());
  Hive.registerAdapter(LicenseStateAdapter());

  final controller = AppStateController();
  await controller.init();

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const ReceiptGeneratorApp(),
    ),
  );
}

class ReceiptGeneratorApp extends StatelessWidget {
  const ReceiptGeneratorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
      ),
      home: const RootShell(),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _selectedIndex = 0;

  bool _isCheckingLicense = true;
  bool _isLicensed = false;

  static const List<Widget> _pages = [
    FrontendPage(),
    BackendPage(),
  ];

  static const List<String> _titles = [
    'Cashier',
    'Manager',
  ];

  @override
  void initState() {
    super.initState();
    _runAutoSyncIfDue();
    _checkLicenseStatus();
    _ensureDeviceRegistered();
  }

  Future<void> _checkLicenseStatus() async {
    final isLicensed = await LicenseService.instance.isLicensedActive();
    if (!mounted) return;
    setState(() {
      _isLicensed = isLicensed;
      _isCheckingLicense = false;
    });
  }

  /// Registers/checks this device in with the central device registry,
  /// if due (first time, or 24+ hours since last check-in). Runs
  /// silently in the background — any correction to trial dates from
  /// a first-time reconciliation takes effect on the next license
  /// check (e.g. next launch), not immediately, so it never interrupts
  /// whatever the cashier is currently doing.
  Future<void> _ensureDeviceRegistered() async {
    final controller = context.read<AppStateController>();
    await LicenseService.instance.ensureDeviceRegistered(
      businessName: controller.settings.businessName,
      whatsappNumber: controller.settings.whatsapp,
    );
  }

  Future<void> _runAutoSyncIfDue() async {
    final controller = context.read<AppStateController>();

    final signedIn = await GoogleDriveService.instance.trySilentSignIn();
    if (!signedIn) return;

    if (controller.isBackupDue) {
      try {
        final bytes = await _buildHistoryExcelBytes(controller);
        final fileName =
            'receipt_history_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
        final result = await GoogleDriveService.instance.uploadExcelBackup(
          bytes: bytes,
          fileName: fileName,
        );
        if (result.success) {
          await controller.recordBackupCompleted();
        }
      } catch (_) {
        // Silent failure is intentional here — this is a background,
        // non-blocking check. The manager can always trigger it manually
        // from the Backup Now button if needed.
      }
    }

    if (controller.isSyncDue) {
      try {
        final result = await GoogleSheetsService.instance.fetchProducts(
          sheetIdOrUrl: controller.settings.googleSheetId,
        );
        if (result.success) {
          await controller.replaceProductPresetsFromSync(
            result.products.map((p) => MapEntry(p.name, p.price)).toList(),
          );
          await controller.recordSyncCompleted();
        }
      } catch (_) {
        // Same reasoning — silent, non-blocking background attempt.
      }
    }
  }

  Future<Uint8List> _buildHistoryExcelBytes(AppStateController controller) async {
    final receipts = controller.receiptHistory;
    final workbook = xls.Excel.createExcel();
    const sheetName = 'Receipt History';
    final sheet = workbook[sheetName];
    if (workbook.getDefaultSheet() != null &&
        workbook.getDefaultSheet() != sheetName) {
      workbook.delete(workbook.getDefaultSheet()!);
    }

    final headers = [
      'Receipt Code',
      'Date',
      'Time',
      'Cashier',
      'Customer',
      'Customer WhatsApp',
      'Items',
      'Subtotal',
      'Discount %',
      'Discount Amount',
      'Coupon Reference',
      'Total Payable',
      'Deposit Paid',
      'Balance Owed',
      'Payment Method',
    ];
    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());

    final dateFormat = DateFormat('yyyy-MM-dd');
    final timeFormat = DateFormat('HH:mm:ss');

    for (final receipt in receipts) {
      final itemsSummary = receipt.items
          .map((item) => '${item.name} x${item.quantity}')
          .join(', ');

      sheet.appendRow([
        xls.TextCellValue(receipt.receiptCode),
        xls.TextCellValue(dateFormat.format(receipt.issuedAt)),
        xls.TextCellValue(timeFormat.format(receipt.issuedAt)),
        xls.TextCellValue(receipt.cashierName),
        xls.TextCellValue(receipt.customerName),
        xls.TextCellValue(receipt.customerWhatsapp),
        xls.TextCellValue(itemsSummary),
        xls.DoubleCellValue(receipt.subtotal),
        xls.DoubleCellValue(receipt.discountPercent),
        xls.DoubleCellValue(receipt.discountAmount),
        xls.TextCellValue(receipt.couponReference),
        xls.DoubleCellValue(receipt.totalPayable),
        xls.DoubleCellValue(receipt.depositPaid),
        xls.DoubleCellValue(receipt.balanceOwed),
        xls.TextCellValue(receipt.paymentMethod),
      ]);
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw Exception('Failed to encode Excel file.');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingLicense) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isLicensed) {
      return LicenseLockoutPage(
        onLicenseActivated: _checkLicenseStatus,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          IconButton(
            tooltip: 'Printer Setup',
            icon: const Icon(Icons.print_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PrinterSetupPage(),
                ),
              );
            },
          ),
          IconButton(
            tooltip: 'Receipt History',
            icon: const Icon(Icons.history_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ReceiptHistoryPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: IndexedStack(index: _selectedIndex, children: _pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'Cashier',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings),
            label: 'Manager',
          ),
        ],
      ),
    );
  }
}