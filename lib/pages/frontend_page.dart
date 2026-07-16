import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product_preset.dart';
import '../models/receipt.dart';
import '../services/thermal_printer_service.dart';
import '../services/whatsapp_share_service.dart';
import '../state/app_state_controller.dart';
import '../widgets/receipt_preview_widget.dart';

class FrontendPage extends StatefulWidget {
  const FrontendPage({super.key});

  @override
  State<FrontendPage> createState() => _FrontendPageState();
}

class _FrontendPageState extends State<FrontendPage> {
  final GlobalKey<FormState> _customerFormKey = GlobalKey<FormState>();
  final TextEditingController _customerNameController =
      TextEditingController();
  final TextEditingController _customerWhatsappController =
      TextEditingController();

  final TextEditingController _itemNameController = TextEditingController();
  final TextEditingController _itemPriceController = TextEditingController();
  final TextEditingController _quantityController =
      TextEditingController(text: '1');
  final TextEditingController _discountController =
      TextEditingController(text: '0');
  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _depositController = TextEditingController();

  ProductPreset? _selectedPreset;
  String _paymentMethod = 'Cash';
  bool _customerFieldsValid = false;

  @override
  void initState() {
    super.initState();
    _customerNameController.addListener(_revalidateCustomerFields);
    _customerWhatsappController.addListener(_revalidateCustomerFields);
    _depositController.addListener(() => setState(() {}));
  }

  void _revalidateCustomerFields() {
    final valid = _customerNameController.text.trim().isNotEmpty &&
        _customerWhatsappController.text.trim().isNotEmpty;
    if (valid != _customerFieldsValid) {
      setState(() => _customerFieldsValid = valid);
    }
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerWhatsappController.dispose();
    _itemNameController.dispose();
    _itemPriceController.dispose();
    _quantityController.dispose();
    _discountController.dispose();
    _couponController.dispose();
    _depositController.dispose();
    super.dispose();
  }

  void _onPresetSelected(ProductPreset? preset) {
    setState(() {
      _selectedPreset = preset;
      if (preset != null) {
        _itemNameController.text = preset.name;
        _itemPriceController.text = preset.price.toStringAsFixed(2);
      }
    });
  }

  void _addItemToReceipt(BuildContext context) {
    final controller = context.read<AppStateController>();
    final name = _itemNameController.text.trim();
    final price = double.tryParse(_itemPriceController.text.trim());
    final quantity = int.tryParse(_quantityController.text.trim());

    if (name.isEmpty || price == null || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid description and price.')),
      );
      return;
    }
    if (quantity == null || quantity <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantity must be at least 1.')),
      );
      return;
    }

    if (_selectedPreset != null && _selectedPreset!.name == name) {
      controller.addToCart(_selectedPreset!, quantity: quantity);
    } else {
      controller.addManualItemToCart(
        name: name,
        unitPrice: price,
        quantity: quantity,
      );
    }

    setState(() {
      _selectedPreset = null;
      _itemNameController.clear();
      _itemPriceController.clear();
      _quantityController.text = '1';
    });
  }

  void _applyDiscount(AppStateController controller, String value) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed >= 0 && parsed <= 100) {
      controller.setDiscountPercent(parsed);
    }
  }

  double _resolveDepositPaid(double totalPayable) {
    final entered = double.tryParse(_depositController.text.trim());
    if (entered == null || entered <= 0) return totalPayable;
    if (entered >= totalPayable) return totalPayable;
    return entered;
  }

  double _resolveBalanceOwed(double totalPayable) {
    final deposit = _resolveDepositPaid(totalPayable);
    final balance = totalPayable - deposit;
    return balance < 0 ? 0 : balance;
  }

  Future<void> _processReceipt(BuildContext context) async {
    final controller = context.read<AppStateController>();
    if (!_customerFormKey.currentState!.validate()) return;
    if (controller.cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item to the receipt.')),
      );
      return;
    }

    final depositPaid = _resolveDepositPaid(controller.totalPayable);

    try {
      final receipt = await controller.finalizeAndSaveReceipt(
        cashierName: 'Front Desk',
        customerName: _customerNameController.text.trim(),
        customerWhatsapp: _customerWhatsappController.text.trim(),
        paymentMethod: _paymentMethod,
        couponReference: _couponController.text.trim(),
        depositPaid: depositPaid,
      );

      if (!context.mounted) return;
      _customerNameController.clear();
      _customerWhatsappController.clear();
      _discountController.text = '0';
      _couponController.clear();
      _depositController.clear();
      setState(() => _paymentMethod = 'Cash');

      showDialog(
        context: context,
        builder: (_) => _ReceiptResultDialog(receipt: receipt),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not process receipt: $e')),
      );
    }
  }

  Widget _buildHeader(BuildContext context) {
    final settings = context.watch<AppStateController>().settings;
    final socialChips = <Widget>[
      if (settings.whatsapp.isNotEmpty)
        _SocialChip(icon: Icons.chat_outlined, label: settings.whatsapp),
      if (settings.website.isNotEmpty)
        _SocialChip(icon: Icons.language_outlined, label: settings.website),
      if (settings.instagram.isNotEmpty)
        _SocialChip(icon: Icons.camera_alt_outlined, label: settings.instagram),
      if (settings.facebook.isNotEmpty)
        _SocialChip(icon: Icons.facebook_outlined, label: settings.facebook),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              settings.businessName,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (settings.address.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                settings.address,
                style: TextStyle(color: Colors.grey.shade700),
              ),
            ],
            if (socialChips.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: socialChips),
            ],
            if (settings.footnote.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                settings.footnote,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _customerFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Customer Details',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _customerNameController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Customer name is required'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _customerWhatsappController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.chat_outlined),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'WhatsApp number is required'
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemEntry(BuildContext context) {
    final controller = context.watch<AppStateController>();
    final presets = controller.productPresets;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add Item',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ProductPreset?>(
              initialValue: _selectedPreset,
              decoration: const InputDecoration(
                labelText: 'Select Preset Product',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              items: [
                const DropdownMenuItem<ProductPreset?>(
                  value: null,
                  child: Text('-- Manual Entry --'),
                ),
                ...presets.map(
                  (preset) => DropdownMenuItem<ProductPreset?>(
                    value: preset,
                    child: Text(
                      '${preset.name} (${controller.settings.currencySymbol}${preset.price.toStringAsFixed(2)})',
                    ),
                  ),
                ),
              ],
              onChanged: _onPresetSelected,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _itemNameController,
              decoration: const InputDecoration(
                labelText: 'Item Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemPriceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Unit Price',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Quantity',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _discountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Overall Discount %',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.percent_outlined),
              ),
              onChanged: (value) => _applyDiscount(controller, value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _couponController,
              decoration: const InputDecoration(
                labelText: 'Coupon Reference (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_offer_outlined),
                hintText: 'e.g. SAVE10, Staff-Approved',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: () => _addItemToReceipt(context),
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('Add Item to Receipt'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsTable(BuildContext context, double width) {
    final controller = context.watch<AppStateController>();
    final cart = controller.cart;
    final currency = controller.settings.currencySymbol;
    final isWide = width >= 700;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Receipt Items',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (cart.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No items added yet.')),
              )
            else if (isWide)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Description')),
                    DataColumn(label: Text('Unit Price')),
                    DataColumn(label: Text('Qty')),
                    DataColumn(label: Text('Line Total')),
                    DataColumn(label: Text('')),
                  ],
                  rows: cart.map((item) {
                    return DataRow(cells: [
                      DataCell(Text(item.name)),
                      DataCell(Text('$currency${item.unitPrice.toStringAsFixed(2)}')),
                      DataCell(Text('${item.quantity}')),
                      DataCell(Text('$currency${item.lineTotal.toStringAsFixed(2)}')),
                      DataCell(
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => controller.removeFromCart(item.id),
                        ),
                      ),
                    ]);
                  }).toList(),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: cart.length,
                  itemBuilder: (context, index) {
                    final item = cart[index];
                    return ListTile(
                      title: Text(item.name),
                      subtitle: Text(
                        '$currency${item.unitPrice.toStringAsFixed(2)} x ${item.quantity}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$currency${item.lineTotal.toStringAsFixed(2)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => controller.removeFromCart(item.id),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryPanel(BuildContext context) {
    final controller = context.watch<AppStateController>();
    final currency = controller.settings.currencySymbol;
    final totalPayable = controller.totalPayable;
    final depositPaid = _resolveDepositPaid(totalPayable);
    final balanceOwed = _resolveBalanceOwed(totalPayable);
    final hasPartialDeposit = _depositController.text.trim().isNotEmpty &&
        (double.tryParse(_depositController.text.trim()) ?? 0) > 0 &&
        balanceOwed > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Order Summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _summaryRow('Subtotal', controller.subtotal, currency),
            _summaryRow(
              'Discount (${controller.discountPercent.toStringAsFixed(1)}%)',
              -controller.discountAmount,
              currency,
            ),
            const Divider(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Amount Payable',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '$currency${totalPayable.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _depositController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Deposit Paid (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.savings_outlined),
                hintText: 'Leave blank if paid in full',
              ),
            ),
            if (hasPartialDeposit) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summaryRow('Deposit Paid', depositPaid, currency),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Balance Owed',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade800,
                            ),
                          ),
                          Text(
                            '$currency${balanceOwed.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              items: const [
                DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                DropdownMenuItem(value: 'Transfer', child: Text('Transfer')),
                DropdownMenuItem(value: 'POS', child: Text('POS')),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _paymentMethod = value);
              },
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_customerFieldsValid && controller.cart.isNotEmpty)
                    ? () => _processReceipt(context)
                    : null,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text('Process Receipt'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, double value, String currency) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$currency${value.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 900;

            final leftColumn = SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 12),
                  _buildCustomerForm(),
                  const SizedBox(height: 12),
                  _buildItemEntry(context),
                  const SizedBox(height: 12),
                  _buildItemsTable(context, constraints.maxWidth),
                  if (!isWide) const SizedBox(height: 12),
                  if (!isWide) _buildSummaryPanel(context),
                ],
              ),
            );

            if (!isWide) {
              return leftColumn;
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: leftColumn),
                SizedBox(
                  width: 360,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                    child: _buildSummaryPanel(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Post-checkout dialog showing the full receipt preview, with independent
/// Print and Share actions the cashier can trigger in any order.
class _ReceiptResultDialog extends StatefulWidget {
  final Receipt receipt;

  const _ReceiptResultDialog({required this.receipt});

  @override
  State<_ReceiptResultDialog> createState() => _ReceiptResultDialogState();
}

class _ReceiptResultDialogState extends State<_ReceiptResultDialog> {
  bool _isPrinting = false;
  bool _isSharing = false;

  Future<void> _handlePrint(AppStateController controller) async {
    setState(() => _isPrinting = true);
    final result = await ThermalPrinterService.instance.printReceipt(
      receipt: widget.receipt,
      business: controller.settings,
    );
    if (!mounted) return;
    setState(() => _isPrinting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Future<void> _handleShare(AppStateController controller) async {
    setState(() => _isSharing = true);
    try {
      final result = await WhatsappShareService.instance
          .shareReceiptDetailsToCustomer(
        receipt: widget.receipt,
        business: controller.settings,
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
          content: Text('Failed to share receipt: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppStateController>();

    return AlertDialog(
      title: const Text('Receipt Processed'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: ReceiptPreviewWidget(
            receipt: widget.receipt,
            business: controller.settings,
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _isPrinting ? null : () => _handlePrint(controller),
          icon: _isPrinting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print_outlined),
          label: Text(_isPrinting ? 'Printing...' : 'Print'),
        ),
        TextButton.icon(
          onPressed: _isSharing ? null : () => _handleShare(controller),
          icon: _isSharing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.share_outlined),
          label: Text(_isSharing ? 'Sharing...' : 'Share'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _SocialChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SocialChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      visualDensity: VisualDensity.compact,
    );
  }
}