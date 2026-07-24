import 'dart:io';

import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/product_preset.dart';
import '../services/google_drive_service.dart';
import '../services/google_sheets_service.dart';
import '../services/license_service.dart';
import '../state/app_state_controller.dart';

class BackendPage extends StatefulWidget {
  const BackendPage({super.key});

  @override
  State<BackendPage> createState() => _BackendPageState();
}

class _BackendPageState extends State<BackendPage> {
  bool _unlocked = false;
  final TextEditingController _passwordController = TextEditingController();
  String? _authError;
  bool _isExporting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _attemptUnlock(AppStateController controller) {
    final entered = _passwordController.text;
    if (controller.verifyManagerPassword(entered)) {
      setState(() {
        _unlocked = true;
        _authError = null;
        _passwordController.clear();
      });
    } else {
      setState(() {
        _authError = 'Incorrect password. Try again.';
      });
    }
  }

  Widget _buildLockScreen(BuildContext context) {
    final controller = context.read<AppStateController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Manager Access')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                const Text(
                  'This area is password protected.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Manager Password',
                    border: const OutlineInputBorder(),
                    errorText: _authError,
                  ),
                  onSubmitted: (_) => _attemptUnlock(controller),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _attemptUnlock(controller),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Unlock'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
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

  Future<void> _exportHistoryToExcel(BuildContext context) async {
    final controller = context.read<AppStateController>();
    setState(() => _isExporting = true);

    try {
      final bytes = await _buildHistoryExcelBytes(controller);
      final fileName =
          'receipt_history_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(bytes, flush: true);

      if (!context.mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath, name: fileName)],
          text: 'Receipt history export ($fileName)',
        ),
      );

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${controller.receiptHistory.length} receipts. Choose "Save to Downloads" or your preferred app.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return _buildLockScreen(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manager Backend'),
        actions: [
          IconButton(
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_outline),
            onPressed: () => setState(() => _unlocked = false),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 900;
          if (isWide) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _BusinessInfoForm(),
                          const SizedBox(height: 16),
                          const _ChangePasswordCard(),
                          const SizedBox(height: 16),
                          const _LicenseStatusCard(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _ProductsSection(width: constraints.maxWidth),
                          const SizedBox(height: 16),
                          _buildExportCard(context),
                          const SizedBox(height: 16),
                          _GoogleSyncCard(
                            onBuildExcelBytes: () =>
                                _buildHistoryExcelBytes(
                                    context.read<AppStateController>()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BusinessInfoForm(),
                const SizedBox(height: 16),
                const _ChangePasswordCard(),
                const SizedBox(height: 16),
                const _LicenseStatusCard(),
                const SizedBox(height: 16),
                _ProductsSection(width: constraints.maxWidth),
                const SizedBox(height: 16),
                _buildExportCard(context),
                const SizedBox(height: 16),
                _GoogleSyncCard(
                  onBuildExcelBytes: () =>
                      _buildHistoryExcelBytes(context.read<AppStateController>()),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildExportCard(BuildContext context) {
    final controller = context.watch<AppStateController>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Receipt History Export',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${controller.receiptHistory.length} receipts stored permanently.',
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed:
                  _isExporting ? null : () => _exportHistoryToExcel(context),
              icon: _isExporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.file_download_outlined),
              label: Text(
                _isExporting ? 'Exporting...' : 'Export History to Excel',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessInfoForm extends StatefulWidget {
  @override
  State<_BusinessInfoForm> createState() => _BusinessInfoFormState();
}

class _BusinessInfoFormState extends State<_BusinessInfoForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _addressController;
  late TextEditingController _whatsappController;
  late TextEditingController _websiteController;
  late TextEditingController _instagramController;
  late TextEditingController _facebookController;
  late TextEditingController _footnoteController;
  late TextEditingController _currencyController;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      final settings = context.read<AppStateController>().settings;
      _titleController = TextEditingController(text: settings.businessName);
      _addressController = TextEditingController(text: settings.address);
      _whatsappController = TextEditingController(text: settings.whatsapp);
      _websiteController = TextEditingController(text: settings.website);
      _instagramController =
          TextEditingController(text: settings.instagram);
      _facebookController = TextEditingController(text: settings.facebook);
      _footnoteController = TextEditingController(text: settings.footnote);
      _currencyController =
          TextEditingController(text: settings.currencySymbol);
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _addressController.dispose();
    _whatsappController.dispose();
    _websiteController.dispose();
    _instagramController.dispose();
    _facebookController.dispose();
    _footnoteController.dispose();
    _currencyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = context.read<AppStateController>();
    await controller.updateBusinessDetails(
      businessName: _titleController.text.trim(),
      address: _addressController.text.trim(),
      whatsapp: _whatsappController.text.trim(),
      website: _websiteController.text.trim(),
      instagram: _instagramController.text.trim(),
      facebook: _facebookController.text.trim(),
      footnote: _footnoteController.text.trim(),
      currencySymbol: _currencyController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Business information saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Business Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
                decoration: const InputDecoration(
                  labelText: 'Title Heading',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Title heading is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _currencyController,
                decoration: const InputDecoration(
                  labelText: 'Currency Symbol',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money_outlined),
                  hintText: 'e.g. ₦, \$, £, €',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Currency symbol is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _whatsappController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.chat_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _websiteController,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Website',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.language_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _instagramController,
                decoration: const InputDecoration(
                  labelText: 'Instagram',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.camera_alt_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _facebookController,
                decoration: const InputDecoration(
                  labelText: 'Facebook',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.facebook_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _footnoteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Footnote',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. Thank you for shopping with us!',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Business Information'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePasswordCard extends StatefulWidget {
  const _ChangePasswordCard();

  @override
  State<_ChangePasswordCard> createState() => _ChangePasswordCardState();
}

class _ChangePasswordCardState extends State<_ChangePasswordCard> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _currentPasswordController =
      TextEditingController();
  final TextEditingController _newPasswordController =
      TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    final controller = context.read<AppStateController>();
    final currentEntered = _currentPasswordController.text;
    final newPassword = _newPasswordController.text.trim();

    if (!controller.verifyManagerPassword(currentEntered)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Current password is incorrect.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await controller.updateManagerPassword(newPassword);
      if (!mounted) return;
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Manager password updated successfully.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update password: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Change Manager Password',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Update the password required to access this Manager Backend.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _currentPasswordController,
                obscureText: _obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureCurrent
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscureCurrent = !_obscureCurrent),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Enter your current password'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _newPasswordController,
                obscureText: _obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscureNew = !_obscureNew),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter a new password';
                  }
                  if (value.trim().length < 4) {
                    return 'Password must be at least 4 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Confirm your new password';
                  }
                  if (value.trim() != _newPasswordController.text.trim()) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _changePassword,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.password_outlined),
                label: Text(
                  _isSaving ? 'Updating...' : 'Update Password',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Read-only card showing this device's ID and current trial/subscription/
/// Lifetime status — for the manager's own reference and for support
/// (reading the device ID over WhatsApp to request a code, or so you can
/// tell them their status directly).
class _LicenseStatusCard extends StatefulWidget {
  const _LicenseStatusCard();

  @override
  State<_LicenseStatusCard> createState() => _LicenseStatusCardState();
}

class _LicenseStatusCardState extends State<_LicenseStatusCard> {
  LicenseStatusSummary? _summary;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final summary = await LicenseService.instance.getStatusSummary();
    if (mounted) setState(() => _summary = summary);
  }

  String _statusLine(LicenseStatusSummary summary) {
    if (summary.isLifetime) {
      return 'Lifetime license — no expiry.';
    }

    final expiry = summary.effectiveExpiry;
    if (expiry == null) {
      return 'License status unavailable.';
    }

    final dateStr = DateFormat('MMM d, yyyy').format(expiry.toLocal());
    final planWord = summary.planLabel == 'subscription' ? 'Subscription' : 'Trial';

    return '$planWord active — ${summary.daysRemaining} day(s) remaining (until $dateStr).';
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'License Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (summary == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              Text(_statusLine(summary)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Device ID: ${summary.deviceId}',
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy device ID',
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: summary.deviceId),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Device ID copied.'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProductsSection extends StatelessWidget {
  final double width;

  const _ProductsSection({required this.width});

  Future<void> _showProductDialog(
    BuildContext context, {
    ProductPreset? existing,
  }) async {
    final nameController =
        TextEditingController(text: existing?.name ?? '');
    final priceController = TextEditingController(
      text: existing != null ? existing.price.toStringAsFixed(2) : '',
    );
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(existing == null ? 'Add Product' : 'Edit Product'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Description',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) =>
                      (value == null || value.trim().isEmpty)
                          ? 'Required'
                          : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Unit Price',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(value ?? '');
                    if (parsed == null || parsed < 0) {
                      return 'Enter a valid price';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final controller = dialogContext.read<AppStateController>();
                final name = nameController.text.trim();
                final price = double.parse(priceController.text.trim());
                if (existing == null) {
                  await controller.addProductPreset(name: name, price: price);
                } else {
                  await controller.updateProductPreset(
                    existing.id,
                    name: name,
                    price: price,
                  );
                }
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ProductPreset product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove Product'),
        content: Text('Remove "${product.name}" from active presets?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await context.read<AppStateController>().deactivateProductPreset(
            product.id,
          );
    }
  }

  Future<void> _showBulkImportDialog(BuildContext context) async {
    final bulkTextController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Bulk Import Products'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter one product per line, as:\nProduct Name, Unit Price',
                    style: TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bulkTextController,
                    maxLines: 12,
                    minLines: 6,
                    decoration: const InputDecoration(
                      hintText:
                          'Custom T-Shirt Print, 3500\nVinyl Banner (per sqm), 2500\nBusiness Card (100 pcs), 5000',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? 'Enter at least one product line'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;

                final controller = dialogContext.read<AppStateController>();
                final lines = bulkTextController.text.split('\n');

                int addedCount = 0;
                final List<String> skippedLines = [];

                for (final rawLine in lines) {
                  final line = rawLine.trim();
                  if (line.isEmpty) continue;

                  final commaIndex = line.lastIndexOf(',');
                  if (commaIndex == -1) {
                    skippedLines.add('$line (missing comma)');
                    continue;
                  }

                  final name = line.substring(0, commaIndex).trim();
                  final priceText = line.substring(commaIndex + 1).trim();
                  final price = double.tryParse(priceText);

                  if (name.isEmpty) {
                    skippedLines.add('$line (missing name)');
                    continue;
                  }
                  if (price == null || price < 0) {
                    skippedLines.add('$line (invalid price)');
                    continue;
                  }

                  await controller.addProductPreset(name: name, price: price);
                  addedCount++;
                }

                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }

                if (context.mounted) {
                  final summary = StringBuffer('$addedCount product(s) added.');
                  if (skippedLines.isNotEmpty) {
                    summary.write(' ${skippedLines.length} line(s) skipped.');
                  }
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(summary.toString()),
                      backgroundColor: skippedLines.isEmpty
                          ? Colors.green.shade700
                          : Colors.orange.shade700,
                    ),
                  );

                  if (skippedLines.isNotEmpty) {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Skipped Lines'),
                        content: SingleChildScrollView(
                          child: Text(skippedLines.join('\n')),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  }
                }
              },
              child: const Text('Import'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppStateController>();
    final products = controller.productPresets;
    final currency = controller.settings.currencySymbol;
    final isWide = width >= 700;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Preset Products',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _showBulkImportDialog(context),
                      icon: const Icon(Icons.playlist_add_outlined),
                      label: const Text('Bulk Import'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showProductDialog(context),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Product'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (products.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No products added yet.')),
              )
            else if (isWide)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Item Description')),
                    DataColumn(label: Text('Unit Price')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: products.map((product) {
                    return DataRow(
                      cells: [
                        DataCell(Text(product.name)),
                        DataCell(
                          Text('$currency${product.price.toStringAsFixed(2)}'),
                        ),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _showProductDialog(
                                  context,
                                  existing: product,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () =>
                                    _confirmDelete(context, product),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return Card(
                    child: ListTile(
                      title: Text(product.name),
                      subtitle: Text(
                        '$currency${product.price.toStringAsFixed(2)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _showProductDialog(
                              context,
                              existing: product,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _confirmDelete(context, product),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Manages Google account connection, the linked product Sheet, and manual
/// Backup Now / Sync Products Now actions. Silent sign-in is attempted on
/// first build so a previously-connected account is restored automatically
/// without prompting the manager again.
class _GoogleSyncCard extends StatefulWidget {
  final Future<Uint8List> Function() onBuildExcelBytes;

  const _GoogleSyncCard({required this.onBuildExcelBytes});

  @override
  State<_GoogleSyncCard> createState() => _GoogleSyncCardState();
}

class _GoogleSyncCardState extends State<_GoogleSyncCard> {
  bool _isSigningIn = false;
  bool _isBackingUp = false;
  bool _isSyncing = false;
  bool _checkedSilentSignIn = false;
  late final TextEditingController _sheetController;

  @override
  void initState() {
    super.initState();
    _sheetController = TextEditingController();
    _attemptSilentSignIn();
  }

  Future<void> _attemptSilentSignIn() async {
    await GoogleDriveService.instance.trySilentSignIn();
    if (mounted) {
      setState(() => _checkedSilentSignIn = true);
    }
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    setState(() => _isSigningIn = true);
    final result = await GoogleDriveService.instance.signIn();
    if (!mounted) return;
    setState(() => _isSigningIn = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Future<void> _handleSignOut() async {
    await GoogleDriveService.instance.signOut();
    if (mounted) setState(() {});
  }

  Future<void> _handleBackupNow() async {
    setState(() => _isBackingUp = true);
    try {
      final bytes = await widget.onBuildExcelBytes();
      final fileName =
          'receipt_history_backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final result = await GoogleDriveService.instance.uploadExcelBackup(
        bytes: bytes,
        fileName: fileName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor:
              result.success ? Colors.green.shade700 : Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Backup failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  Future<void> _handleSaveSheetId(AppStateController controller) async {
    await controller.updateGoogleSheetId(_sheetController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Google Sheet link saved.')),
    );
  }

  Future<void> _handleSyncNow(AppStateController controller) async {
    final sheetId = controller.settings.googleSheetId;
    if (sheetId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paste and save a Google Sheet link first.'),
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);
    try {
      final result = await GoogleSheetsService.instance.fetchProducts(
        sheetIdOrUrl: sheetId,
      );
      if (!result.success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }

      await controller.replaceProductPresetsFromSync(
        result.products.map((p) => MapEntry(p.name, p.price)).toList(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppStateController>();
    final isSignedIn = GoogleDriveService.instance.isSignedIn;
    final signedInEmail = GoogleDriveService.instance.signedInEmail;

    if (_sheetController.text.isEmpty &&
        controller.settings.googleSheetId.isNotEmpty) {
      _sheetController.text = controller.settings.googleSheetId;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Google Drive Backup & Product Sync',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Automatically back up receipt history and keep preset products in sync with a Google Sheet.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (!_checkedSilentSignIn)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!isSignedIn)
              ElevatedButton.icon(
                onPressed: _isSigningIn ? null : _handleSignIn,
                icon: _isSigningIn
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata_outlined, size: 24),
                label: Text(
                  _isSigningIn ? 'Connecting...' : 'Connect Google Account',
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Connected: ${signedInEmail ?? ""}',
                        style: TextStyle(color: Colors.green.shade800),
                      ),
                    ),
                    TextButton(
                      onPressed: _handleSignOut,
                      child: const Text('Disconnect'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isBackingUp ? null : _handleBackupNow,
                icon: _isBackingUp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.backup_outlined),
                label: Text(_isBackingUp ? 'Backing Up...' : 'Backup Now'),
              ),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Remote Product Sheet',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Paste the link to a Google Sheet with Product Name in column A and Unit Price in column B.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sheetController,
                decoration: const InputDecoration(
                  labelText: 'Google Sheet Link or ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.table_chart_outlined),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _handleSaveSheetId(controller),
                      child: const Text('Save Link'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSyncing
                          ? null
                          : () => _handleSyncNow(controller),
                      icon: _isSyncing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync_outlined),
                      label: Text(_isSyncing ? 'Syncing...' : 'Sync Now'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}