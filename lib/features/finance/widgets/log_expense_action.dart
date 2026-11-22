import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../expense_repository.dart';
import '../finance_boxes.dart';
import '../finance_repository.dart';
import '../models/finance_settings.dart';
import '../screens/cashier_expense_page.dart';

/// The single cashier "Log Expense" button. Drop it into the app bar actions.
/// It hides itself when finance data is unavailable or when the manager has
/// switched off "Allow cashiers to log expenses", and reacts to that setting
/// immediately.
class LogExpenseAction extends StatelessWidget {
  const LogExpenseAction({super.key});

  @override
  Widget build(BuildContext context) {
    if (!ExpenseRepository.instance.isReady) return const SizedBox.shrink();
    final Box<FinanceSettings> settingsBox;
    try {
      settingsBox = Hive.box<FinanceSettings>(FinanceBoxes.settingsBox);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<Box<FinanceSettings>>(
      valueListenable: settingsBox.listenable(),
      builder: (context, _, child) {
        if (!FinanceRepository.instance.settings.allowCashierExpenses) {
          return const SizedBox.shrink();
        }
        return IconButton(
          tooltip: 'Log Expense',
          icon: const Icon(Icons.payments_outlined),
          onPressed: () {
            try {
              Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CashierExpensePage()));
            } catch (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not open Log Expense.')));
            }
          },
        );
      },
    );
  }
}
