import 'package:flutter/material.dart';

import '../asset_repository.dart';
import '../finance_boxes.dart';
import '../expense_repository.dart';
import '../finance_repository.dart';
import '../legacy_link_repository.dart';
import '../loan_repository.dart';
import '../screens/assets_page.dart';
import '../screens/expenses_page.dart';
import '../screens/finance_settings_page.dart';
import '../screens/loans_page.dart';
import '../screens/settle_balances_page.dart';
import '../settlement_repository.dart';
import '../screens/unmatched_balance_payments_page.dart';

/// The single entry card shown inside the Manager Backend (behind the manager
/// password). Later phases add Reports, Assets and Loans here.
class FinanceHubCard extends StatelessWidget {
  const FinanceHubCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ready = FinanceRepository.instance.isReady;
    final legacyReady = ready && LegacyLinkRepository.instance.isReady;
    final unmatched =
        legacyReady ? LegacyLinkRepository.instance.needsReviewCount() : 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Finance', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (!ready)
              Text(
                'Finance data could not be opened on this device. The rest of the app is not affected.'
                '${FinanceBoxes.failures.isEmpty ? '' : '\n(${FinanceBoxes.failures.keys.join(', ')})'}',
              ),
            if (ready && ExpenseRepository.instance.isReady) ...[
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ManagerExpensesPage()));
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not open Expenses.')));
                  }
                },
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('Expenses'),
              ),
              const SizedBox(height: 8),
            ],
            if (legacyReady) ...[
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const UnmatchedBalancePaymentsPage()));
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Could not open Unmatched balance payments.')));
                  }
                },
                icon: const Icon(Icons.link_off_outlined),
                label: Text(unmatched > 0
                    ? 'Unmatched balance payments ($unmatched)'
                    : 'Unmatched balance payments'),
              ),
              const SizedBox(height: 8),
            ],
            if (ready && SettlementRepository.instance.isReady) ...[
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const SettleBalancesPage()));
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not open Settle with adjustment.')));
                  }
                },
                icon: const Icon(Icons.balance_outlined),
                label: const Text('Settle with adjustment'),
              ),
              const SizedBox(height: 8),
            ],
            if (ready && AssetRepository.instance.isReady) ...[
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ManagerAssetsPage()));
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not open Assets.')));
                  }
                },
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Assets'),
              ),
              const SizedBox(height: 8),
            ],
            if (ready && LoanRepository.instance.isReady) ...[
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ManagerLoansPage()));
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not open Loans.')));
                  }
                },
                icon: const Icon(Icons.account_balance_outlined),
                label: const Text('Loans'),
              ),
              const SizedBox(height: 8),
            ],
            if (ready)
              OutlinedButton.icon(
                onPressed: () {
                  try {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const FinanceSettingsPage()));
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Could not open Finance Settings.')));
                  }
                },
                icon: const Icon(Icons.tune),
                label: const Text('Finance Settings'),
              ),
          ],
        ),
      ),
    );
  }
}
