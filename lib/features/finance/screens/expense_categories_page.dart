import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../finance_repository.dart';
import '../models/expense_category.dart';

/// Manager-only: add, rename and archive expense categories.
/// Categories are never deleted, so old expenses always keep their category.
class ExpenseCategoriesPage extends StatelessWidget {
  const ExpenseCategoriesPage({super.key});

  static const Map<String, String> _groupTitles = {
    ExpenseCategory.groupDirect: 'Direct costs',
    ExpenseCategory.groupOperating: 'Operating costs',
    ExpenseCategory.groupNotInPnl: 'Not in P&L',
  };

  static const Map<String, String> _groupHints = {
    ExpenseCategory.groupDirect:
        'Materials bought to produce your work (toner, ink, paper...).',
    ExpenseCategory.groupOperating: 'Running costs of the business.',
    ExpenseCategory.groupNotInPnl:
        'Money that leaves the business but is not a business cost. Shown in Cashflow only, never reduces profit.',
  };

  @override
  Widget build(BuildContext context) {
    final repo = FinanceRepository.instance;
    final box = repo.expenseCategoryBox;

    return Scaffold(
      appBar: AppBar(title: const Text('Expense categories')),
      floatingActionButton: box == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add category'),
            ),
      body: box == null
          ? const Center(child: Text('Categories are not available.'))
          : ValueListenableBuilder<Box<ExpenseCategory>>(
              valueListenable: box.listenable(),
              builder: (context, box, child) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    for (final group in ExpenseCategory.groups) ...[
                      Text(_groupTitles[group]!,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(_groupHints[group]!,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Card(
                        child: Column(
                          children: [
                            for (final c in repo.expenseCategories(group))
                              _tile(context, repo, c),
                            if (repo.expenseCategories(group).isEmpty)
                              const ListTile(title: Text('No categories yet')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _tile(BuildContext context, FinanceRepository repo, ExpenseCategory c) {
    return ListTile(
      title: Text(
        c.name,
        style: c.archived
            ? TextStyle(color: Theme.of(context).disabledColor)
            : null,
      ),
      subtitle: c.archived ? const Text('Archived (hidden from pickers)') : null,
      onTap: () => _showRenameDialog(context, repo, c),
      trailing: IconButton(
        tooltip: c.archived ? 'Restore' : 'Archive',
        icon: Icon(c.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
        onPressed: () async {
          try {
            await repo.setExpenseCategoryArchived(c, !c.archived);
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not update the category.')));
            }
          }
        },
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context) async {
    final nameCtrl = TextEditingController();
    var group = ExpenseCategory.groupOperating;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: InputDecoration(
                    labelText: 'Name', errorText: error),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: group,
                decoration: const InputDecoration(labelText: 'Group'),
                items: [
                  for (final g in ExpenseCategory.groups)
                    DropdownMenuItem(value: g, child: Text(_groupTitles[g]!)),
                ],
                onChanged: (v) {
                  if (v != null) setLocal(() => group = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final result = await FinanceRepository.instance
                    .addExpenseCategory(nameCtrl.text, group);
                if (result == null) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } else {
                  setLocal(() => error = result);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }

  Future<void> _showRenameDialog(
      BuildContext context, FinanceRepository repo, ExpenseCategory c) async {
    final nameCtrl = TextEditingController(text: c.name);
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Rename category'),
          content: TextField(
            controller: nameCtrl,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Name', errorText: error),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                final result = await repo.renameExpenseCategory(c, nameCtrl.text);
                if (result == null) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } else {
                  setLocal(() => error = result);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
  }
}
