import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../asset_repository.dart';
import '../asset_rules.dart';
import '../finance_repository.dart';
import '../models/asset.dart';

/// Manager-only form to add a fixed asset. Purchases of equipment are entered
/// here, not in Expenses. A past purchase date is fine: equipment the shop
/// already owned is entered with its original date and cost.
class AssetForm extends StatefulWidget {
  final VoidCallback? onSaved;

  const AssetForm({super.key, this.onSaved});

  @override
  State<AssetForm> createState() => _AssetFormState();
}

class _AssetFormState extends State<AssetForm> {
  static const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cost = TextEditingController();
  final _vendor = TextEditingController();
  final _life = TextEditingController();
  final _residual = TextEditingController();
  final _rate = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _date;
  String? _categoryId;
  String? _paidFrom;
  bool _opening = false;
  bool _reducing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = AssetRepository.dateOnly(DateTime.now());
    final paid = FinanceRepository.instance.settings.paidFromOptions;
    _paidFrom = paid.isEmpty ? null : paid.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _cost.dispose();
    _vendor.dispose();
    _life.dispose();
    _residual.dispose();
    _rate.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? _parse(String text) {
    final t = text.replaceAll(',', '').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _pickDate() async {
    final today = AssetRepository.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      lastDate: today,
    );
    if (!mounted) return;
    if (picked != null) setState(() => _date = AssetRepository.dateOnly(picked));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final cost = _parse(_cost.text) ?? 0;
    final threshold = FinanceRepository.instance.settings.capitalisationThreshold;
    if (AssetRules.belowThreshold(
        cost: cost, threshold: threshold, isOpeningBalance: _opening)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Record as an expense instead?'),
          content: Text(
              'This purchase is below your capitalisation threshold of '
              '${threshold.toStringAsFixed(2)}. Small items are usually recorded '
              'in Expenses, not as assets.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Save as asset anyway')),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    setState(() => _saving = true);
    String? error;
    try {
      error = await AssetRepository.instance.addAsset(
        name: _name.text,
        categoryId: _categoryId ?? '',
        purchaseDate: _date,
        cost: cost,
        paymentMethod: _opening ? '' : (_paidFrom ?? ''),
        vendor: _vendor.text,
        usefulLifeMonths: int.tryParse(_life.text.trim()) ?? 0,
        residualValue: _parse(_residual.text) ?? 0,
        method: _reducing ? Asset.methodReducingBalance : Asset.methodStraightLine,
        annualRate: _reducing ? _parse(_rate.text) : null,
        isOpeningBalance: _opening,
        notes: _notes.text,
      );
    } catch (_) {
      error = 'Could not save the asset. Please try again.';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Asset saved.')));
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final cats = AssetRepository.instance.categories();
    final paidFromOptions = FinanceRepository.instance.settings.paidFromOptions;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Asset name'),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Enter the asset name' : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _categoryId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in cats)
                DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              _categoryId = v;
              final cat = cats.where((c) => c.id == v);
              if (cat.isNotEmpty) {
                _life.text = cat.first.defaultUsefulLifeMonths.toString();
              }
            },
            validator: (v) => v == null ? 'Choose a category' : null,
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Purchase date',
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _cost,
            keyboardType: _decimalKeyboard,
            decoration: const InputDecoration(labelText: 'Cost'),
            validator: (v) {
              final n = _parse(v ?? '');
              if (n == null || n <= 0) return 'Enter a cost above zero';
              return null;
            },
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Bought before I started using this app'),
            subtitle: const Text(
                'Enter the original purchase date and cost. No cash is recorded.'),
            value: _opening,
            onChanged: (v) => setState(() => _opening = v),
          ),
          if (!_opening) ...[
            DropdownButtonFormField<String>(
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
          ],
          TextFormField(
            controller: _vendor,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Vendor (optional)'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _life,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Useful life (months)',
                helperText: 'Suggested from the category. Confirm with your accountant.'),
            validator: (v) {
              final n = int.tryParse((v ?? '').trim());
              if (n == null || n < 1) return 'Enter the useful life in months';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _residual,
            keyboardType: _decimalKeyboard,
            decoration: const InputDecoration(
                labelText: 'Residual value (optional, default 0)'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = _parse(v);
              if (n == null || n < 0) return 'Enter a valid amount';
              return null;
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            initialValue: _reducing,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Depreciation method'),
            items: const [
              DropdownMenuItem(value: false, child: Text('Straight-line')),
              DropdownMenuItem(value: true, child: Text('Reducing balance')),
            ],
            onChanged: (v) => setState(() => _reducing = v ?? false),
          ),
          if (_reducing) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _rate,
              keyboardType: _decimalKeyboard,
              decoration:
                  const InputDecoration(labelText: 'Annual rate (percent)'),
              validator: (v) {
                final n = _parse(v ?? '');
                if (n == null || n <= 0 || n > 100) {
                  return 'Enter a rate between 0 and 100';
                }
                return null;
              },
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: const Text('Save asset'),
          ),
        ],
      ),
    );
  }
}
