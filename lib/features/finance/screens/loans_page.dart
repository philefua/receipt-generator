import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state_controller.dart';
import '../loan_repository.dart';
import '../widgets/loan_form.dart';
import 'loan_detail_page.dart';

/// Manager-only: loans received, what is still owed on each, and the way into
/// each loan's repayments. Reached from the Finance card in the Manager
/// Backend, behind the password. Loan money is never entered in Sales or
/// Expenses.
class ManagerLoansPage extends StatelessWidget {
  const ManagerLoansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = LoanRepository.instance;
    final loans = repo.loanBox;
    final txs = repo.transactionBox;
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
      floatingActionButton: (loans == null || txs == null)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAdd(context),
              icon: const Icon(Icons.add),
              label: const Text('Add loan'),
            ),
      body: (loans == null || txs == null)
          ? const Center(child: Text('Loans are not available.'))
          : AnimatedBuilder(
              animation: Listenable.merge([loans.listenable(), txs.listenable()]),
              builder: (context, _) => _content(context),
            ),
    );
  }

  void _showAdd(BuildContext context) {
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
              Text('Add loan', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              LoanForm(onSaved: () => Navigator.of(ctx).pop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final repo = LoanRepository.instance;
    final symbol = context.read<AppStateController>().settings.currencySymbol;
    final money = NumberFormat('#,##0.00');
    String fmt(int minor) => '$symbol${money.format(minor / 100)}';
    final dayFmt = DateFormat('d MMM yyyy');

    final snaps = repo.snapshots();
    final totals = repo.totals();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Loans still owed (${totals.activeCount})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total outstanding',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(fmt(totals.outstandingMinor),
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Money borrowed is not income and repaying the principal is '
                  'not an expense. Only the interest is a cost. Settled and '
                  'voided loans are not counted.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (snaps.isEmpty)
          const Card(child: ListTile(title: Text('No loans yet')))
        else
          Card(
            child: Column(
              children: [
                for (final s in snaps)
                  ListTile(
                    title: Text(
                      s.loan.lenderName,
                      style: s.isVoided
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough)
                          : null,
                    ),
                    subtitle: Text([
                      LoanForm.typeLabel(s.loan.lenderType),
                      dayFmt.format(s.loan.dateReceived),
                      if (s.loan.isOpeningBalance) 'Opening balance',
                      if (s.isSettled) 'Settled',
                      if (s.isVoided) 'Voided',
                    ].join(' · ')),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmt(
                            (s.loan.principal * 100).round())),
                        if (!s.isVoided)
                          Text('Owes ${fmt(s.outstandingMinor)}',
                              style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => LoanDetailPage(loanId: s.loan.id))),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
