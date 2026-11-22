import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../expense_repository.dart';
import '../finance_repository.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';

/// The one expense entry form, used by the cashier page (role cashier) and the
/// Manager page (role manager). The role comes from where the form is opened,
/// because the app has no cashier login.
///
/// Cashier: date, category (direct and operating only), amount, paid from,
/// description. Manager: the same plus vendor, input VAT, WHT and the
/// Not in P&L categories.
class ExpenseForm extends StatefulWidget {
  final String role;
  final VoidCallback? onSaved;

  const ExpenseForm({super.key, required this.role, this.onSaved});

  bool get isManager => role == Expense.roleManager;

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  static const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  final _vendor = TextEditingController();
  final _inputVat = TextEditingController();
  final _wht = TextEditingController();

  late DateTime _date;
  String? _categoryId;
  String? _paidFrom;
  bool _saving = false;

  /// A dropdown made with initialValue does not clear itself after a save.
  /// Changing this number changes the dropdown keys, which rebuilds them empty.
  int _resetKey = 0;

  @override
  void initState() {
    super.initState();
    _date = ExpenseRepository.dateOnly(DateTime.now());
    _paidFrom = _defaultPaidFrom();
  }

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    _vendor.dispose();
    _inputVat.dispose();
    _wht.dispose();
    super.dispose();
  }

  String? _defaultPaidFrom() {
    final list = FinanceRepository.instance.settings.paidFromOptions;
    return list.isEmpty ? null : list.first;
  }

  List<ExpenseCategory> _pickableCategories() {
    final repo = FinanceRepository.instance;
    final groups = widget.isManager
        ? ExpenseCategory.groups
        : const [ExpenseCategory.groupDirect, ExpenseCategory.groupOperating];
    return [
      for (final g in groups) ...repo.expenseCategories(g, includeArchived: false),
    ];
  }

  double? _parse(String text) {
    final t = text.replaceAll(',', '').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  String? _optionalMoney(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final n = _parse(v);
    if (n == null || n < 0) return 'Enter a valid amount';
    return null;
  }

  Future<void> _pickDate() async {
    final today = ExpenseRepository.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (!mounted) return;
    if (picked != null) setState(() => _date = ExpenseRepository.dateOnly(picked));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    String? error;
    try {
      error = await ExpenseRepository.instance.addExpense(
        date: _date,
        categoryId: _categoryId ?? '',
        amount: _parse(_amount.text) ?? 0,
        paidFrom: _paidFrom ?? '',
        description: _description.text,
        vendor: widget.isManager ? _vendor.text : null,
        inputVat: widget.isManager ? _parse(_inputVat.text) : null,
        whtAmount: widget.isManager ? _parse(_wht.text) : null,
        role: widget.role,
      );
    } catch (_) {
      error = 'Could not save the expense. Please try again.';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {
      _amount.clear();
      _description.clear();
      _vendor.clear();
      _inputVat.clear();
      _wht.clear();
      _categoryId = null;
      _paidFrom = _defaultPaidFrom();
      _date = ExpenseRepository.dateOnly(DateTime.now());
      _resetKey++;
    });
    _formKey.currentState?.reset();
    messenger.showSnackBar(const SnackBar(content: Text('Expense saved.')));
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cats = _pickableCategories();
    final paidFromOptions = FinanceRepository.instance.settings.paidFromOptions;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date',
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('category_$_resetKey'),
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in cats)
                DropdownMenuItem(
                  value: c.id,
                  child: Text(
                    c.group == ExpenseCategory.groupNotInPnl
                        ? '${c.name} (not in P&L)'
                        : c.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => _categoryId = v,
            validator: (v) => v == null ? 'Choose a category' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amount,
            keyboardType: _decimalKeyboard,
            decoration: const InputDecoration(labelText: 'Amount'),
            validator: (v) {
              final n = _parse(v ?? '');
              if (n == null || n <= 0) return 'Enter an amount above zero';
              return null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('paid_$_resetKey'),
            initialValue: _paidFrom,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Paid from'),
            items: [
              for (final o in paidFromOptions)
                DropdownMenuItem(value: o, child: Text(o)),
            ],
            onChanged: (v) => _paidFrom = v,
            validator: (v) => v == null ? 'Choose how it was paid' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _description,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Description (optional)'),
          ),
          if (widget.isManager) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _vendor,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Vendor (optional)'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _inputVat,
              keyboardType: _decimalKeyboard,
              decoration: const InputDecoration(
                  labelText: 'Input VAT (optional, information only)'),
              validator: _optionalMoney,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _wht,
              keyboardType: _decimalKeyboard,
              decoration: const InputDecoration(
                  labelText: 'WHT (optional, information only)'),
              validator: _optionalMoney,
            ),
            const SizedBox(height: 8),
            Text(
              'Buying equipment? Use Assets. Paying a loan? Use Loans.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Save expense'),
          ),
        ],
      ),
    );
  }
}
