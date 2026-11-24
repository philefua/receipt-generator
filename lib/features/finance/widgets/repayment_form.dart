import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../finance_repository.dart';
import '../loan_repository.dart';
import '../models/loan.dart';

/// Manager-only form to record one repayment. Enter the principal and the
/// interest exactly as the lender's statement shows. The app never works out
/// interest. Principal reduces the loan and is not an expense.
class RepaymentForm extends StatefulWidget {
  final Loan loan;
  final VoidCallback? onSaved;

  const RepaymentForm({super.key, required this.loan, this.onSaved});

  @override
  State<RepaymentForm> createState() => _RepaymentFormState();
}

class _RepaymentFormState extends State<RepaymentForm> {
  static const _decimalKeyboard = TextInputType.numberWithOptions(decimal: true);

  final _formKey = GlobalKey<FormState>();
  final _principal = TextEditingController();
  final _interest = TextEditingController();
  final _note = TextEditingController();

  late DateTime _date;
  String? _paidFrom;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _date = LoanRepository.dateOnly(DateTime.now());
    final paid = FinanceRepository.instance.settings.paidFromOptions;
    _paidFrom = paid.isEmpty ? null : paid.first;
  }

  @override
  void dispose() {
    _principal.dispose();
    _interest.dispose();
    _note.dispose();
    super.dispose();
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
    final today = LoanRepository.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: widget.loan.dateReceived,
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
      error = await LoanRepository.instance.addRepayment(
        loanId: widget.loan.id,
        date: _date,
        principalAmount: _parse(_principal.text) ?? 0,
        interestAmount: _parse(_interest.text) ?? 0,
        paymentMethod: _paidFrom ?? '',
        note: _note.text,
      );
    } catch (_) {
      error = 'Could not save the repayment. Please try again.';
    }
    if (!mounted) return;
    setState(() => _saving = false);
    final messenger = ScaffoldMessenger.of(context);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Repayment saved.')));
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
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date paid',
                suffixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(DateFormat('EEE, d MMM yyyy').format(_date)),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _principal,
            keyboardType: _decimalKeyboard,
            decoration: const InputDecoration(
                labelText: 'Principal (reduces the loan)'),
            validator: _optionalMoney,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _interest,
            keyboardType: _decimalKeyboard,
            decoration:
                const InputDecoration(labelText: 'Interest (a finance cost)'),
            validator: _optionalMoney,
          ),
          const SizedBox(height: 12),
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
          TextFormField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 8),
          Text(
            'Use the amounts on the lender\'s statement. Bank fees and charges '
            'go to Expenses under "Bank charges", not here.',
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
            label: const Text('Save repayment'),
          ),
        ],
      ),
    );
  }
}
