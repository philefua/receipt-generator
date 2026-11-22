import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../models/expense_options.dart';
import '../state/app_state_controller.dart';

final NumberFormat _money = NumberFormat('#,##0.00');

/// Daily expense record, opened from the app bar on the Cashier screen.
///
/// Pick a day, see what came in (receipts) and what went out (expenses),
/// add expenses, and void mistaken ones (voiding needs the manager
/// password). Exporting to Excel / Google Drive is handled by the Manager
/// backend.
class DailyExpensesPage extends StatefulWidget {
  const DailyExpensesPage({super.key});

  @override
  State<DailyExpensesPage> createState() => _DailyExpensesPageState();
}

class _DailyExpensesPageState extends State<DailyExpensesPage> {
  DateTime _day = DateTime.now();

  bool get _isToday {
    final now = DateTime.now();
    return _day.year == now.year &&
        _day.month == now.month &&
        _day.day == now.day;
  }

  void _shiftDay(int delta) {
    setState(() => _day = DateTime(_day.year, _day.month, _day.day + delta));
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _day = picked);
    }
  }

  void _openAddExpense() {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddExpensePage(initialDate: _day),
      ),
    );
  }

  Future<void> _confirmVoid(Expense expense) async {
    final voided = await showDialog<bool>(
      context: context,
      builder: (_) => _VoidExpenseDialog(expense: expense),
    );
    if (voided == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${expense.voucher} voided.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppStateController>();
    final currency = controller.settings.currencySymbol;
    final expenses = controller.expensesForDay(_day);
    final activeCount = expenses.where((e) => !e.isVoided).length;
    final cashPaid = controller.totalCashPaidForDay(_day);
    final collected = controller.salesCollectedForDay(_day);
    final net = collected - cashPaid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Expenses'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAddExpense,
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Previous day',
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _shiftDay(-1),
                      ),
                      Expanded(
                        child: TextButton(
                          onPressed: _pickDay,
                          child: Text(
                            '${_isToday ? 'Today  •  ' : ''}'
                            '${DateFormat('EEE, d MMM yyyy').format(_day)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Next day',
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _isToday ? null : () => _shiftDay(1),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _summaryRow(
                        'Sales collected',
                        '$currency${_money.format(collected)}',
                      ),
                      const SizedBox(height: 6),
                      _summaryRow(
                        'Cash paid out',
                        '$currency${_money.format(cashPaid)}',
                      ),
                      const Divider(height: 20),
                      _summaryRow(
                        'Net for the day',
                        '${net < 0 ? '-' : ''}$currency${_money.format(net.abs())}',
                        bold: true,
                        color: net < 0
                            ? Theme.of(context).colorScheme.error
                            : Colors.green.shade700,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (expenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text('No expenses recorded for this day.'),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                  child: Text(
                    '$activeCount expense${activeCount == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final e in expenses) _buildExpenseCard(e, currency),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpenseCard(Expense e, String currency) {
    final lines = <String>[
      e.description,
      '${e.costType} • ${e.category}',
      '${e.paymentAccount} • ${e.receiptStatus}',
      if (e.inputVat > 0 || e.whtDeducted > 0)
        'Net $currency${_money.format(e.netAmount)}'
            ' • VAT $currency${_money.format(e.inputVat)}'
            ' • WHT $currency${_money.format(e.whtDeducted)}',
      if (e.isVoided) 'VOIDED',
    ];

    return Card(
      child: ListTile(
        title: Text(
          '${e.voucher}  •  ${e.vendor}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: e.isVoided ? TextDecoration.lineThrough : null,
            color: e.isVoided ? Colors.grey : null,
          ),
        ),
        subtitle: Text(lines.join('\n')),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$currency${_money.format(e.totalCashPaid)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: e.isVoided ? Colors.grey : null,
              ),
            ),
            if (!e.isVoided)
              IconButton(
                tooltip: 'Void',
                icon: const Icon(Icons.block_outlined),
                onPressed: () => _confirmVoid(e),
              ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    final style = TextStyle(
      fontSize: bold ? 17 : 15,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

/// Asks for the manager password, then voids the expense. Owns its own text
/// controller so it is disposed together with the dialog.
class _VoidExpenseDialog extends StatefulWidget {
  final Expense expense;

  const _VoidExpenseDialog({required this.expense});

  @override
  State<_VoidExpenseDialog> createState() => _VoidExpenseDialogState();
}

class _VoidExpenseDialogState extends State<_VoidExpenseDialog> {
  final TextEditingController _passwordController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final controller = context.read<AppStateController>();
    setState(() {
      _busy = true;
      _error = null;
    });
    final done = await controller.voidExpense(
      widget.expense.id,
      managerPassword: _passwordController.text,
    );
    if (!mounted) return;
    if (done) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _busy = false;
        _error = 'Incorrect password.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Void ${widget.expense.voucher}?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${widget.expense.description}" will be removed from the '
            'day\'s totals and from the export. The manager password is '
            'needed to do this.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Manager password',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
            onSubmitted: (_) => _busy ? null : _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Checking...' : 'Void'),
        ),
      ],
    );
  }
}

/// Full-screen form for one expense. Field order follows the columns of
/// tab 3_Expense_Ledger in the financial workbook.
class AddExpensePage extends StatefulWidget {
  final DateTime initialDate;

  const AddExpensePage({super.key, required this.initialDate});

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  late DateTime _date;
  late final String _voucherPreview;

  final TextEditingController _vendorController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _netController = TextEditingController();
  final TextEditingController _vatController = TextEditingController();
  final TextEditingController _whtController = TextEditingController();
  final TextEditingController _recordedByController =
      TextEditingController(text: 'Front Desk');
  final TextEditingController _notesController = TextEditingController();

  String? _costType;
  String? _category;
  String? _paymentAccount;
  String? _receiptStatus;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate;
    _date = DateTime(d.year, d.month, d.day);
    _voucherPreview = context.read<AppStateController>().nextVoucher();
    _netController.addListener(_refresh);
    _vatController.addListener(_refresh);
    _whtController.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _vendorController.dispose();
    _descriptionController.dispose();
    _netController.dispose();
    _vatController.dispose();
    _whtController.dispose();
    _recordedByController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Tax Remittance, Drawings and Loan Repayment cannot carry VAT or WHT.
  bool get _vatWhtAllowed {
    final costType = _costType;
    return costType == null || ExpenseOptions.allowsVatAndWht(costType);
  }

  bool get _isCapex {
    final costType = _costType;
    return costType != null && ExpenseOptions.requiresAssetTag(costType);
  }

  /// Empty text counts as 0. Returns null if the text is not a valid number.
  static double? _parseMoney(String text) {
    final cleaned = text.replaceAll(',', '').trim();
    if (cleaned.isEmpty) return 0.0;
    return double.tryParse(cleaned);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day));
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _save() async {
    final controller = context.read<AppStateController>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final net = _parseMoney(_netController.text);
    final vat = _vatWhtAllowed ? _parseMoney(_vatController.text) : 0.0;
    final wht = _vatWhtAllowed ? _parseMoney(_whtController.text) : 0.0;

    if (vat == null) {
      _showError('Input VAT must be a number.');
      return;
    }
    if (wht == null) {
      _showError('WHT must be a number.');
      return;
    }

    final problem = controller.validateExpense(
      date: _date,
      vendor: _vendorController.text,
      description: _descriptionController.text,
      costType: _costType ?? '',
      category: _category ?? '',
      netAmount: net,
      inputVat: vat,
      whtDeducted: wht,
      paymentAccount: _paymentAccount ?? '',
      receiptStatus: _receiptStatus ?? '',
      notes: _notesController.text,
    );
    if (problem != null) {
      _showError(problem);
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await controller.addExpense(
        date: _date,
        vendor: _vendorController.text,
        description: _descriptionController.text,
        costType: _costType!,
        category: _category!,
        netAmount: net!,
        inputVat: vat,
        whtDeducted: wht,
        paymentAccount: _paymentAccount!,
        receiptStatus: _receiptStatus!,
        recordedBy: _recordedByController.text,
        notes: _notesController.text,
      );
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Saved ${saved.voucher}.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(e is ArgumentError ? '${e.message}' : 'Could not save: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = context.read<AppStateController>().settings.currencySymbol;

    final net = _parseMoney(_netController.text) ?? 0.0;
    final vat =
        _vatWhtAllowed ? (_parseMoney(_vatController.text) ?? 0.0) : 0.0;
    final wht =
        _vatWhtAllowed ? (_parseMoney(_whtController.text) ?? 0.0) : 0.0;
    final totalCashPaid = net + vat - wht;

    final costType = _costType;
    final categories =
        costType == null ? <String>[] : ExpenseOptions.categoriesFor(costType);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Expense'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Voucher / Ref #',
                  border: OutlineInputBorder(),
                  helperText: 'Assigned automatically',
                ),
                child: Text(_voucherPreview),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vendorController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Vendor / Payee',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Description & Qty',
                  hintText: 'e.g. 5 rolls 3.2m flex banner',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _costType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Cost Type',
                  border: OutlineInputBorder(),
                ),
                items: ExpenseOptions.costTypes
                    .map((c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c),
                        ))
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _costType = value;
                    _category = null;
                    if (value != null &&
                        !ExpenseOptions.allowsVatAndWht(value)) {
                      _vatController.clear();
                      _whtController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('category-$_costType'),
                initialValue: _category,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Expense Category',
                  border: const OutlineInputBorder(),
                  helperText:
                      _costType == null ? 'Choose a Cost Type first' : null,
                ),
                items: categories
                    .map((c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c),
                        ))
                    .toList(),
                onChanged: _costType == null
                    ? null
                    : (value) => setState(() => _category = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _netController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Net Expense (excl. VAT)',
                  helperText: 'Amount before VAT and before WHT',
                  prefixText: '$currency ',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _vatController,
                enabled: _vatWhtAllowed,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'Input VAT Paid',
                  helperText:
                      _vatWhtAllowed ? null : 'Not applicable to this cost type',
                  prefixText: '$currency ',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _whtController,
                enabled: _vatWhtAllowed,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'WHT Deducted',
                  helperText: _vatWhtAllowed
                      ? 'Withheld from the vendor, if any'
                      : 'Not applicable to this cost type',
                  prefixText: '$currency ',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Total Cash Paid',
                  border: OutlineInputBorder(),
                  helperText: 'Net + VAT - WHT (calculated)',
                ),
                child: Text(
                  '$currency${_money.format(totalCashPaid)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paymentAccount,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Payment Account',
                  border: OutlineInputBorder(),
                ),
                items: ExpenseOptions.paymentAccounts
                    .map((c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _paymentAccount = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _receiptStatus,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Receipt / Audit Status',
                  border: OutlineInputBorder(),
                ),
                items: ExpenseOptions.receiptStatuses
                    .map((c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _receiptStatus = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _recordedByController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Recorded By',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: _isCapex
                      ? 'Serial / Asset Tag (required for CapEx)'
                      : 'Notes (optional)',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Saving...' : 'Save Expense'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}