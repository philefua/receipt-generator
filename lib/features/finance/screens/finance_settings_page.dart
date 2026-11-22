import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state_controller.dart';
import '../finance_repository.dart';
import 'expense_categories_page.dart';

/// Manager-only finance settings. Reached from the Manager Backend.
class FinanceSettingsPage extends StatefulWidget {
  const FinanceSettingsPage({super.key});

  @override
  State<FinanceSettingsPage> createState() => _FinanceSettingsPageState();
}

class _FinanceSettingsPageState extends State<FinanceSettingsPage> {
  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  final _repo = FinanceRepository.instance;
  final _formKey = GlobalKey<FormState>();

  late bool _allowCashierExpenses;
  late int _fyStartMonth;
  late bool _vatEnabled;
  DateTime? _openingCashDate;
  List<String> _paidFrom = [];

  final _taxId = TextEditingController();
  final _vatRate = TextEditingController();
  final _estTaxRate = TextEditingController();
  final _openingCash = TextEditingController();
  final _capThreshold = TextEditingController();
  final _newPaidFrom = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final s = _repo.settings;
    _allowCashierExpenses = s.allowCashierExpenses;
    _fyStartMonth = s.financialYearStartMonth.clamp(1, 12).toInt();
    _vatEnabled = s.vatEnabled;
    _openingCashDate = s.openingCashDate;
    _paidFrom = List<String>.of(s.paidFromOptions);
    _taxId.text = s.taxId;
    _vatRate.text = _fmt(s.vatRatePercent);
    _estTaxRate.text = _fmt(s.estimatedTaxRatePercent);
    _openingCash.text = _fmt(s.openingCashBalance);
    _capThreshold.text = _fmt(s.capitalisationThreshold);
  }

  @override
  void dispose() {
    _taxId.dispose();
    _vatRate.dispose();
    _estTaxRate.dispose();
    _openingCash.dispose();
    _capThreshold.dispose();
    _newPaidFrom.dispose();
    super.dispose();
  }

  String _fmt(double v) => v == 0 ? '0' : v.toStringAsFixed(2);

  double _parse(String text) =>
      double.parse((double.tryParse(text.replaceAll(',', '').trim()) ?? 0)
          .toStringAsFixed(2));

  String? _validateAmount(String? v, {double max = double.infinity}) {
    final t = (v ?? '').replaceAll(',', '').trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    if (n == null) return 'Enter a number';
    if (n < 0) return 'Cannot be negative';
    if (n > max) return 'Cannot be more than ${max.toStringAsFixed(0)}';
    return null;
  }

  Future<void> _pickOpeningDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _openingCashDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null && mounted) setState(() => _openingCashDate = picked);
  }

  Future<void> _addPaidFrom() async {
    final name = _newPaidFrom.text.trim();
    if (name.isEmpty) return;
    if (_paidFrom.any((o) => o.toLowerCase() == name.toLowerCase())) {
      _snack('That option already exists.');
      return;
    }
    setState(() {
      _paidFrom = [..._paidFrom, name];
      _newPaidFrom.clear();
    });
  }

  void _removePaidFrom(String name) {
    if (_paidFrom.length <= 1) {
      _snack('Keep at least one option.');
      return;
    }
    setState(() => _paidFrom = _paidFrom.where((o) => o != name).toList());
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final s = _repo.settings;
      s.allowCashierExpenses = _allowCashierExpenses;
      s.financialYearStartMonth = _fyStartMonth;
      s.taxId = _taxId.text.trim();
      s.vatEnabled = _vatEnabled;
      s.vatRatePercent = _parse(_vatRate.text);
      s.estimatedTaxRatePercent = _parse(_estTaxRate.text);
      s.openingCashBalance = _parse(_openingCash.text);
      s.openingCashDate = _openingCashDate;
      s.capitalisationThreshold = _parse(_capThreshold.text);
      s.paidFromOptions = List<String>.of(_paidFrom);
      await _repo.saveSettings(s);
      if (!mounted) return;
      _snack('Finance settings saved.');
    } catch (_) {
      if (!mounted) return;
      _snack('Could not save finance settings. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final symbol = context.read<AppStateController>().settings.currencySymbol;
    final dateText = _openingCashDate == null
        ? 'Not set'
        : DateFormat('d MMM yyyy').format(_openingCashDate!);

    return Scaffold(
      appBar: AppBar(title: const Text('Finance Settings')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Allow cashiers to log expenses'),
                    subtitle: const Text(
                        'Shows a Log Expense button on the cashier screen. Cashiers only see their own entries for today.'),
                    value: _allowCashierExpenses,
                    onChanged: (v) => setState(() => _allowCashierExpenses = v),
                  ),
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Expense categories'),
                    subtitle: const Text('Add, rename or archive'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (!_repo.isReady) {
                        _snack('Categories are not available on this device.');
                        return;
                      }
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ExpenseCategoriesPage()));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _section('Report details', [
              TextFormField(
                controller: _taxId,
                decoration: const InputDecoration(
                    labelText: 'Tax ID (optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _fyStartMonth,
                decoration: const InputDecoration(
                    labelText: 'Financial year starts in',
                    border: OutlineInputBorder()),
                items: [
                  for (var i = 1; i <= 12; i++)
                    DropdownMenuItem(value: i, child: Text(_months[i - 1])),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _fyStartMonth = v);
                },
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('VAT enabled'),
                value: _vatEnabled,
                onChanged: (v) => setState(() => _vatEnabled = v),
              ),
              if (_vatEnabled)
                TextFormField(
                  controller: _vatRate,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'VAT rate (%)', border: OutlineInputBorder()),
                  validator: (v) => _validateAmount(v, max: 100),
                ),
              if (_vatEnabled) const SizedBox(height: 12),
              TextFormField(
                controller: _estTaxRate,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Estimated income tax rate (%)',
                  helperText:
                      'Optional. Shown in reports as an estimate. 0 means off.',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _validateAmount(v, max: 100),
              ),
            ]),
            const SizedBox(height: 16),
            _section('Opening cash', [
              TextFormField(
                controller: _openingCash,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Opening cash balance ($symbol)',
                  helperText: 'Used as the starting point of the Cashflow sheet.',
                  border: const OutlineInputBorder(),
                ),
                validator: _validateAmount,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('As at date'),
                subtitle: Text(dateText),
                trailing: const Icon(Icons.calendar_today_outlined),
                onTap: _pickOpeningDate,
              ),
            ]),
            const SizedBox(height: 16),
            _section('Assets', [
              TextFormField(
                controller: _capThreshold,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Capitalisation threshold ($symbol)',
                  helperText:
                      'Optional. Purchases below this suggest recording an expense instead. 0 means off.',
                  border: const OutlineInputBorder(),
                ),
                validator: _validateAmount,
              ),
            ]),
            const SizedBox(height: 16),
            _section('Paid from options', [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final o in _paidFrom)
                    InputChip(label: Text(o), onDeleted: () => _removePaidFrom(o)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPaidFrom,
                      decoration: const InputDecoration(
                          labelText: 'New option', border: OutlineInputBorder()),
                      onSubmitted: (_) => _addPaidFrom(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Add',
                    onPressed: _addPaidFrom,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Old expenses keep the text they were saved with if you remove an option.',
                style: TextStyle(fontSize: 12),
              ),
            ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
