import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/receipt.dart';
import '../../../services/thermal_printer_service.dart';
import '../../../services/whatsapp_share_service.dart';
import '../../../state/app_state_controller.dart';
import '../balance_math.dart';
import '../balance_repository.dart';
import '../widgets/balance_receipt_preview.dart';

/// Cashier screen for a customer paying off what they owe. Completely separate
/// from the sale flow: it never touches the cart, the sale counter or the
/// original receipt. It finds the original sale, shows what is outstanding,
/// and saves the payment as a new balance receipt.
class BalancePaymentPage extends StatefulWidget {
  const BalancePaymentPage({super.key});

  @override
  State<BalancePaymentPage> createState() => _BalancePaymentPageState();
}

class _BalancePaymentPageState extends State<BalancePaymentPage> {
  final _repo = BalanceRepository.instance;
  final _codeController = TextEditingController();
  final _amountController = TextEditingController();

  BalanceLookup? _lookup;
  String _paymentMethod = 'Cash';
  int _resetKey = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _codeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  double? get _amount {
    final t = _amountController.text.replaceAll(',', '').trim();
    return t.isEmpty ? null : double.tryParse(t);
  }

  void _find() {
    setState(() {
      _lookup = _repo.lookup(_codeController.text);
      _amountController.clear();
    });
  }

  Future<void> _pickOpenBalance(String currency) async {
    final open = _repo.openBalances();
    if (open.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No customers owe a balance right now.')),
      );
      return;
    }
    final dateFormat = DateFormat('d MMM yyyy');
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Customers who still owe',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              for (final o in open)
                ListTile(
                  title: Text(o.sale.customerName.isNotEmpty
                      ? o.sale.customerName
                      : 'Walk-in customer'),
                  subtitle: Text(
                      '${o.sale.receiptCode} • ${dateFormat.format(o.sale.issuedAt)}'),
                  trailing: Text(
                    '$currency${BalanceMath.fromMinor(o.outstandingMinor).toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () => Navigator.of(ctx).pop(o.sale.receiptCode),
                ),
            ],
          ),
        ),
      ),
    );
    if (code != null && mounted) {
      _codeController.text = code;
      _find();
    }
  }

  Future<void> _save() async {
    final look = _lookup;
    final amount = _amount;
    if (_saving || look == null || !look.found || amount == null) return;

    final controller = context.read<AppStateController>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);

    BalanceSaveResult result;
    try {
      result = await _repo.recordPayment(
        originalCode: look.original!.receiptCode,
        amount: amount,
        paymentMethod: _paymentMethod,
      );
    } catch (_) {
      result = BalanceSaveResult.failure(
          'Could not save the payment. Please try again.');
    }
    if (!mounted) return;
    setState(() => _saving = false);

    final receipt = result.receipt;
    if (receipt == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not save the payment.')),
      );
      return;
    }

    controller.notifyReceiptsChanged();
    setState(() {
      _lookup = null;
      _codeController.clear();
      _amountController.clear();
      _paymentMethod = 'Cash';
      _resetKey++;
    });

    await showDialog<void>(
      context: context,
      builder: (_) => BalanceReceiptResultDialog(receipt: receipt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.read<AppStateController>().settings.currencySymbol;
    String money(int minor) =>
        '$currency${BalanceMath.fromMinor(minor).toStringAsFixed(2)}';

    final look = _lookup;
    final amount = _amount;
    final amountMinor = amount == null ? 0 : BalanceMath.toMinor(amount);
    final tooMuch = look != null && look.found && amountMinor > look.outstandingMinor;
    final canSave = look != null &&
        look.found &&
        look.outstandingMinor > 0 &&
        amountMinor > 0 &&
        !tooMuch &&
        !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Balance Payment')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Use this when a customer comes back to pay what they owe. '
                'It makes a separate balance receipt. The original receipt '
                'is not changed.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeController,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Original receipt number',
                  hintText: 'e.g. ZKq05',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Find',
                    icon: const Icon(Icons.search),
                    onPressed: _find,
                  ),
                ),
                onSubmitted: (_) => _find(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _pickOpenBalance(currency),
                  icon: const Icon(Icons.list_alt_outlined),
                  label: const Text('Pick from customers who owe'),
                ),
              ),
              if (look != null && !look.found) ...[
                const SizedBox(height: 8),
                Text(
                  look.error ?? 'Receipt not found.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (look != null && look.found) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          look.original!.customerName.isNotEmpty
                              ? look.original!.customerName
                              : 'Walk-in customer',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        _row('Original total', money(look.totalMinor)),
                        _row('Already paid', money(look.alreadyPaidMinor)),
                        const Divider(),
                        _row('Balance owed', money(look.outstandingMinor),
                            bold: true),
                        if (look.outstandingMinor == 0)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text('This receipt is fully paid.'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (look != null && look.found && look.outstandingMinor > 0) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount paid now',
                    prefixText: '$currency ',
                    border: const OutlineInputBorder(),
                    errorText: tooMuch
                        ? 'More than the balance owed (${money(look.outstandingMinor)})'
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _amountController.text =
                        BalanceMath.fromMinor(look.outstandingMinor)
                            .toStringAsFixed(2),
                    child: const Text('Pay the full balance'),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  key: ValueKey('method_$_resetKey'),
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'Transfer', child: Text('Transfer')),
                    DropdownMenuItem(value: 'POS', child: Text('POS')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _paymentMethod = v);
                  },
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: canSave ? _save : null,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long_outlined),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Text('Record Balance Payment'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      fontSize: bold ? 17 : 15,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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

/// Shown after a balance payment is saved: preview, print and WhatsApp share.
/// The print and share services pick the balance template on their own.
class BalanceReceiptResultDialog extends StatefulWidget {
  final Receipt receipt;

  const BalanceReceiptResultDialog({super.key, required this.receipt});

  @override
  State<BalanceReceiptResultDialog> createState() =>
      _BalanceReceiptResultDialogState();
}

class _BalanceReceiptResultDialogState
    extends State<BalanceReceiptResultDialog> {
  bool _isPrinting = false;
  bool _isSharing = false;

  void _toast(bool success, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Future<void> _handlePrint(AppStateController controller) async {
    setState(() => _isPrinting = true);
    final result = await ThermalPrinterService.instance.printReceipt(
      receipt: widget.receipt,
      business: controller.settings,
    );
    if (!mounted) return;
    setState(() => _isPrinting = false);
    _toast(result.success, result.message);
  }

  Future<void> _handleShare(AppStateController controller) async {
    setState(() => _isSharing = true);
    try {
      final result =
          await WhatsappShareService.instance.shareReceiptDetailsToCustomer(
        receipt: widget.receipt,
        business: controller.settings,
      );
      if (!mounted) return;
      _toast(result.success, result.message);
    } catch (e) {
      if (!mounted) return;
      _toast(false, 'Failed to share receipt: $e');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppStateController>();
    return AlertDialog(
      title: const Text('Balance Payment Recorded'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: BalanceReceiptPreview(
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
