import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state_controller.dart';
import '../expense_repository.dart';
import '../expense_totals.dart';
import '../finance_repository.dart';
import '../models/expense.dart';
import '../models/expense_category.dart';
import '../widgets/expense_form.dart';

/// Manager-only: full expense list with date and category filters, totals,
/// add, and void. Reached from the Manager Backend (behind the password).
class ManagerExpensesPage extends StatefulWidget {
  const ManagerExpensesPage({super.key});

  @override
  State<ManagerExpensesPage> createState() => _ManagerExpensesPageState();
}

class _ManagerExpensesPageState extends State<ManagerExpensesPage> {
  final _repo = ExpenseRepository.instance;
  late DateTimeRange _range;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    _range = _thisMonth();
  }

  DateTimeRange _thisMonth() {
    final n = DateTime.now();
    return DateTimeRange(
      start: DateTime(n.year, n.month, 1),
      end: DateTime(n.year, n.month + 1, 0),
    );
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (!mounted) return;
    if (picked != null) setState(() => _range = picked);
  }

  void _showAdd() {
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
              Text('Add expense', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              ExpenseForm(
                role: Expense.roleManager,
                onSaved: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final box = _repo.box;
    return Scaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: box == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
      body: box == null
          ? const Center(child: Text('Expenses are not available.'))
          : ValueListenableBuilder<Box<Expense>>(
              valueListenable: box.listenable(),
              builder: (context, _, child) => _buildContent(context),
            ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final symbol = context.read<AppStateController>().settings.currencySymbol;
    final money = NumberFormat('#,##0.00');
    String fmt(double v) => '$symbol${money.format(v)}';
    final dayFmt = DateFormat('d MMM yyyy');

    final list = _repo.query(
        from: _range.start, to: _range.end, categoryId: _categoryId);
    final totals = computeTotals(list);
    final months = totalsByMonth(list);

    final allCategories = [
      for (final g in ExpenseCategory.groups)
        ...FinanceRepository.instance.expenseCategories(g),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        OutlinedButton.icon(
          onPressed: _pickRange,
          icon: const Icon(Icons.date_range),
          label: Text('${dayFmt.format(_range.start)} to ${dayFmt.format(_range.end)}'),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String?>(
                key: ValueKey('filter_$_categoryId'),
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('All categories')),
                  for (final c in allCategories)
                    DropdownMenuItem<String?>(
                      value: c.id,
                      child: Text(c.archived ? '${c.name} (archived)' : c.name,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => setState(() => _categoryId = v),
              ),
            ),
            TextButton(
              onPressed: () => setState(() {
                _range = _thisMonth();
                _categoryId = null;
              }),
              child: const Text('This month'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Totals for the list below',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _totalRow('Direct costs', fmt(totals.direct)),
                _totalRow('Operating costs', fmt(totals.operating)),
                _totalRow('Total expenses', fmt(totals.totalExpenses), bold: true),
                const Divider(),
                _totalRow('Not in P&L (drawings, tax)', fmt(totals.notInPnl)),
                if (months.length > 1) ...[
                  const Divider(),
                  Text('By month', style: Theme.of(context).textTheme.labelLarge),
                  for (final m in months)
                    _totalRow(
                      DateFormat('MMMM yyyy').format(m.key),
                      '${fmt(m.value.totalExpenses)}'
                      '${m.value.notInPnlMinor > 0 ? '  (+ ${fmt(m.value.notInPnl)} not in P&L)' : ''}',
                    ),
                ],
                const SizedBox(height: 4),
                Text('Voided entries are not counted.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (list.isEmpty)
          const Card(child: ListTile(title: Text('No expenses in this range')))
        else
          Card(
            child: Column(
              children: [
                for (final e in list) _tile(context, e, fmt, dayFmt),
              ],
            ),
          ),
      ],
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
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

  Widget _tile(BuildContext context, Expense e, String Function(double) fmt,
      DateFormat dayFmt) {
    final struck = e.isVoided
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    final notInPnl = e.categoryType == ExpenseCategory.groupNotInPnl;
    return ListTile(
      title: Text(_repo.categoryName(e.categoryId), style: struck),
      subtitle: Text([
        dayFmt.format(e.date),
        e.paidFrom,
        if (e.description.isNotEmpty) e.description,
        if (notInPnl) 'Not in P&L',
        if (e.isVoided) 'Voided',
      ].join(' · ')),
      trailing: Text(fmt(e.amount), style: struck),
      onTap: () => _showDetail(context, e, fmt, dayFmt),
    );
  }

  Future<void> _showDetail(BuildContext context, Expense e,
      String Function(double) fmt, DateFormat dayFmt) async {
    final when = DateFormat('d MMM yyyy, HH:mm');
    Widget line(String k, String? v) => (v == null || v.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('$k: $v'),
          );
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_repo.categoryName(e.categoryId)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              line('Amount', fmt(e.amount)),
              line('Date', dayFmt.format(e.date)),
              line('Paid from', e.paidFrom),
              line('Description', e.description),
              line('Vendor', e.vendor),
              line('Input VAT', e.inputVat == null ? null : fmt(e.inputVat!)),
              line('WHT', e.whtAmount == null ? null : fmt(e.whtAmount!)),
              line('Entered by', e.createdByRole),
              line('Saved', when.format(e.createdAt)),
              if (e.isVoided) ...[
                const Divider(),
                line('Voided', when.format(e.voidedAt!)),
                line('Reason', e.voidReason),
                line('Voided by', e.voidedBy),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
          if (!e.isVoided)
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _showVoid(context, e);
              },
              child: const Text('Void'),
            ),
        ],
      ),
    );
  }

  Future<void> _showVoid(BuildContext context, Expense e) async {
    final reasonCtrl = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Void expense'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'The entry stays on record but is left out of totals and reports. This cannot be undone. To correct a mistake, void it and enter a new expense.'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration:
                    InputDecoration(labelText: 'Reason (required)', errorText: error),
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
                  result = await _repo.voidExpense(e, reasonCtrl.text);
                } catch (_) {
                  result = 'Could not void the expense. Please try again.';
                }
                if (result == null) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } else {
                  setLocal(() => error = result);
                }
              },
              child: const Text('Void expense'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }
}
