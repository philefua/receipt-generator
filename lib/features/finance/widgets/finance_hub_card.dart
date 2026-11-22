import 'package:flutter/material.dart';

import '../finance_boxes.dart';
import '../expense_repository.dart';
import '../finance_repository.dart';
import '../screens/expenses_page.dart';
import '../screens/finance_settings_page.dart';

/// The single entry card shown inside the Manager Backend (behind the manager
/// password). Later phases add Reports, Assets and Loans here.
class FinanceHubCard extends StatelessWidget {
  const FinanceHubCard({super.key});

  @override
  Widget build(BuildContext context) {
    final ready = FinanceRepository.instance.isReady;
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
