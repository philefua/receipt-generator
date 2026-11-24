import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state_controller.dart';
import '../balance_math.dart';
import '../loan_repository.dart';
import '../models/loan.dart';
import '../models/loan_transaction.dart';
import '../widgets/loan_form.dart';
import '../widgets/repayment_form.dart';

/// Manager-only: one loan with its figures and repayment history, add
/// repayment, and void for the loan or any repayment (reason required).
class LoanDetailPage extends StatelessWidget {
  final String loanId;

  const LoanDetailPage({super.key, required this.loanId});

  @override
  Widget build(BuildContext context) {
    final repo = LoanRepository.instance;
    final loans = repo.loanBox;
    final txs = repo.transactionBox;
    return Scaffold(
      appBar: AppBar(title: const Text('Loan')),
      body: (loans == null || txs == null)
          ? const Center(child: Text('Loans are not available.'))
          : AnimatedBuilder(
              animation: Listenable.merge([loans.listenable(), txs.listenable()]),
              builder: (context, _) {
                final loan = loans.get(loanId);
                if (loan == null) {
                  return const Center(child: Text('This loan was not found.'));
                }
                return _content(context, loan);
              },
            ),
    );
  }

  Widget _content(BuildContext context, Loan loan) {
    final repo = LoanRepository.instance;
    final symbol = context.read<AppStateController>().settings.currencySymbol;
    final money = NumberFormat('#,##0.00');
    String fmt(int minor) => '$symbol${money.format(minor / 100)}';
    final dayFmt = DateFormat('d MMM yyyy');
    final when = DateFormat('d MMM yyyy, HH:mm');

    final snap = repo.snapshot(loan);
    final repayments = repo.repayments(loan.id);
    final voided = loan.voidedAt != null;

    Widget line(String k, String? v) => (v == null || v.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('$k: $v'),
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loan.lenderName,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                line('Type', LoanForm.typeLabel(loan.lenderType)),
                line(loan.isOpeningBalance ? 'Balance as at' : 'Date received',
                    dayFmt.format(loan.dateReceived)),
                if (loan.isOpeningBalance)
                  line('Entered as', 'Opening balance (no cash recorded)')
                else
                  line('Paid into', loan.receivedInto),
                line('Interest rate',
                    loan.interestRatePercent == null ? null : '${loan.interestRatePercent}% (information only)'),
                line('Term',
                    loan.termMonths == null ? null : '${loan.termMonths} months (information only)'),
                line('Notes', loan.notes),
                line('Entered', when.format(loan.createdAt)),
                if (voided) ...[
                  const Divider(),
                  line('Voided', when.format(loan.voidedAt!)),
                  line('Reason', loan.voidReason),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row(loan.isOpeningBalance ? 'Opening balance' : 'Amount received',
                    fmt(BalanceMath.toMinor(loan.principal))),
                _row('Principal repaid', fmt(snap.principalRepaidMinor)),
                _row('Interest paid', fmt(snap.interestPaidMinor)),
                const Divider(),
                _row('Outstanding', fmt(snap.outstandingMinor), bold: true),
                const SizedBox(height: 4),
                Text(
                  voided
                      ? 'This loan is voided.'
                      : snap.isSettled
                          ? 'Settled: nothing is owed on this loan.'
                          : 'Still owed.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!voided)
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _showAddRepayment(context, loan),
                  icon: const Icon(Icons.add),
                  label: const Text('Add repayment'),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () => _showVoidLoan(context, loan),
                child: const Text('Void loan'),
              ),
            ],
          ),
        const SizedBox(height: 16),
        Text('Repayments (${repayments.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (repayments.isEmpty)
          const Card(child: ListTile(title: Text('No repayments yet')))
        else
          Card(
            child: Column(
              children: [
                for (final t in repayments)
                  _repaymentTile(context, t, fmt, dayFmt),
              ],
            ),
          ),
      ],
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label, style: style)),
          const SizedBox(width: 12),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _repaymentTile(BuildContext context, LoanTransaction t,
      String Function(int) fmt, DateFormat dayFmt) {
    final voided = t.voidedAt != null;
    final struck =
        voided ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
    return ListTile(
      title: Text(
        'Principal ${fmt(BalanceMath.toMinor(t.principalAmount))}  ·  '
        'Interest ${fmt(BalanceMath.toMinor(t.interestAmount))}',
        style: struck,
      ),
      subtitle: Text([
        dayFmt.format(t.date),
        t.paymentMethod,
        if (t.note.isNotEmpty) t.note,
        if (voided) 'Voided: ${t.voidReason ?? ''}',
      ].join(' · ')),
      isThreeLine: voided,
      trailing: voided
          ? null
          : TextButton(
              onPressed: () => _showVoidRepayment(context, t),
              child: const Text('Void'),
            ),
    );
  }

  void _showAddRepayment(BuildContext context, Loan loan) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add repayment', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              RepaymentForm(loan: loan, onSaved: () => Navigator.of(ctx).pop()),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showVoidLoan(BuildContext context, Loan loan) async {
    await _voidDialog(
      context,
      title: 'Void loan',
      message:
          'The loan stays on record but is left out of totals and reports. This cannot be undone. A loan with repayments cannot be voided until its repayments are voided first.',
      confirmLabel: 'Void loan',
      action: (reason) => LoanRepository.instance.voidLoan(loan, reason),
    );
  }

  Future<void> _showVoidRepayment(BuildContext context, LoanTransaction t) async {
    await _voidDialog(
      context,
      title: 'Void repayment',
      message:
          'The repayment stays on record but no longer counts. The balance owed goes back up. This cannot be undone. To correct a mistake, void it and enter the repayment again.',
      confirmLabel: 'Void repayment',
      action: (reason) => LoanRepository.instance.voidRepayment(t, reason),
    );
  }

  Future<void> _voidDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required Future<String?> Function(String reason) action,
  }) async {
    final reasonCtrl = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                    labelText: 'Reason (required)', errorText: error),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                String? result;
                try {
                  result = await action(reasonCtrl.text);
                } catch (_) {
                  result = 'Could not void. Please try again.';
                }
                if (result == null) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } else {
                  setLocal(() => error = result);
                }
              },
              child: Text(confirmLabel),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }
}
