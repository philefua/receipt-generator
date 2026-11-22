import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state_controller.dart';
import '../expense_repository.dart';
import '../finance_repository.dart';
import '../models/expense.dart';
import '../widgets/expense_form.dart';

/// The only cashier-facing finance screen. A simple entry form plus a
/// read-only list of the expenses entered today. No totals, no edit, no void,
/// no reports.
class CashierExpensePage extends StatelessWidget {
  const CashierExpensePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = ExpenseRepository.instance;
    final box = repo.box;
    final allowed = FinanceRepository.instance.settings.allowCashierExpenses;

    Widget body;
    if (!repo.isReady || box == null) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Expenses are not available on this device.'),
        ),
      );
    } else if (!allowed) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Logging expenses is switched off.'),
        ),
      );
    } else {
      final symbol = context.read<AppStateController>().settings.currencySymbol;
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ExpenseForm(role: Expense.roleCashier),
          const SizedBox(height: 24),
          Text('Entered today', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ValueListenableBuilder<Box<Expense>>(
            valueListenable: box.listenable(),
            builder: (context, _, child) {
              final today = repo.enteredTodayByCashier();
              if (today.isEmpty) {
                return const Card(
                    child: ListTile(title: Text('Nothing entered yet today')));
              }
              final money = NumberFormat('#,##0.00');
              return Card(
                child: Column(
                  children: [
                    for (final e in today)
                      ListTile(
                        title: Text(
                          repo.categoryName(e.categoryId),
                          style: e.isVoided
                              ? const TextStyle(
                                  decoration: TextDecoration.lineThrough)
                              : null,
                        ),
                        subtitle: Text([
                          DateFormat('HH:mm').format(e.createdAt),
                          e.paidFrom,
                          if (e.description.isNotEmpty) e.description,
                          if (e.isVoided) 'Voided',
                        ].join(' · ')),
                        trailing: Text(
                          '$symbol${money.format(e.amount)}',
                          style: e.isVoided
                              ? const TextStyle(
                                  decoration: TextDecoration.lineThrough)
                              : null,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Log Expense')),
      body: body,
    );
  }
}
