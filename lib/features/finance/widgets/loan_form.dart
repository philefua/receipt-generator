import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../finance_repository.dart';
import '../loan_repository.dart';
import '../models/loan.dart';

/// Manager-only form to record a loan received. Loan money is never entered in
/// Sales or Expenses. A loan the shop already owed before using the app is
/// entered as its outstanding balance on the date entered, with no cash inflow.
class LoanForm extends StatefulWidget {
  final VoidCallback? onSaved;

  const LoanForm({super.key, this.onSaved});

  static String typeLabel(String t) =>
      t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';

  @override
  State<LoanForm> createState() => _LoanFormState();
}

class _LoanFormState extends State<LoanForm> {
  static const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

  final _formKey = GlobalKey<FormState>();
  final _lender = TextEditingController();
  final _principal = TextEditingController();
  final _rate = TextEditingController();
  final _term = TextEditingController();
  final _notes = TextEditingController();

  late DateTime _date;
  String? _type;
  String? _receivedInto;
  bool _opening = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = LoanRepository.dateOnly(DateTime.now());
    final paid = FinanceRepository.instance.settings.paidFromOptions;
    _receivedInto = paid.isEmpty ? null : paid.first;
  }

  @override
  void dispose() {
    _lender.dispose();
    _principal.dispose();
    _rate.dispose();
    _term.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? _parse(String text) {
    final t = text.replaceAll(',', '').trim();
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _pickDate() async {
    final today = LoanRepository.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1990),
      lastDate: today,
    );
    if (!mounted) return;
    if (picked != null) setState(() => _date = LoanRepository.dateOnly(picked));
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    String? error;
    try {
      error = await LoanRepository.instance.addLoan(
        lenderName: _lender.text,
        lenderType: _type ?? '',
        dateReceived: _date,
        principal: _parse(_principal.text) ?? 0,
        receivedInto: _opening ? '' : (_receivedInto ?? ''),
        interestRatePercent: _parse(_rate.text),
        termMonths: int.tryParse(_term.text.trim()),
        notes: _notes.text,
        isOpeningBalance: _opening,
      );
    } catch (_) {
      error = 'Could not save the loan. Please try again.';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Loan saved.')));
    widget.onSaved?.call();
  }

  @override
  Widget build(BuildContext context) {
    final paidFromOptions = FinanceRepository.instance.settings.paidFromOptions;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _lender,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Lender name'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Enter the lender\'s name'
                : null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Type of lender'),
            items: [
              for (final t in Loan.lenderTypes)
                DropdownMenuItem(value: t, child: Text(LoanForm.typeLabel(t))),
            ],
            onChanged: (v) => _type = v,
            validator: (v) => v == null ? 'Choose the type of lender' : null,
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('I already owed this before using this app'),
            subtitle: const Text(
                'Enter the balance still owed on the date below. No cash is recorded.'),
            value: _opening,
            onChanged: (v) => setState(() => _opening = v),
          ),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: _opening ? 'Balance as at (date)' : 'Date received',
                suffixIcon: const Icon(Icons.calendar_today_outlined),
              ),
              child: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _principal,
            keyboardType: _decimalKeyboard,
            decoration: InputDecoration(
                labelText:
                    _opening ? 'Balance still owed' : 'Amount received'),
            validator: (v) {
              final n = _parse(v ?? '');
              if (n == null || n <= 0) return 'Enter an amount above zero';
              return null;
            },
          ),
          if (!_opening) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _receivedInto,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Paid into'),
              items: [
                for (final o in paidFromOptions)
                  DropdownMenuItem(value: o, child: Text(o)),
              ],
              onChanged: (v) => _receivedInto = v,
              validator: (v) => v == null ? 'Choose where it was paid' : null,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _rate,
            keyboardType: _decimalKeyboard,
            decoration: const InputDecoration(
                labelText: 'Interest rate % (optional, for information only)'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = _parse(v);
              if (n == null || n < 0) return 'Enter a valid rate';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _term,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'Term in months (optional, for information only)'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = int.tryParse(v.trim());
              if (n == null || n < 1) return 'Enter a valid number of months';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _notes,
            textCapitalization: TextCapitalization.sentences,
            decoration:
                const InputDecoration(labelText: 'Purpose or notes (optional)'),
          ),
          const SizedBox(height: 8),
          Text(
            'More money from the same lender later? Enter it as a new loan.',
            style: Theme.of(context).textTheme.bodySmall,
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
            label: const Text('Save loan'),
          ),
        ],
      ),
    );
  }
}
