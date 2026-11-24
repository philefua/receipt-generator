import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state_controller.dart';
import '../balance_math.dart';
import '../balance_repository.dart';
import '../models/receipt_link.dart';
import '../settlement_repository.dart';

/// Manager-only: close a small leftover balance with a written-off amount and
/// a required reason ("Settle with adjustment"). No cash moves. Reached from
/// the Finance card in the Manager Backend, behind the password.
class SettleBalancesPage extends StatefulWidget {
  const SettleBalancesPage({super.key});

  @override
  State<SettleBalancesPage> createState() => _SettleBalancesPageState();
}

class _SettleBalancesPageState extends State<SettleBalancesPage> {
  final _repo = SettlementRepository.instance;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipts = _repo.receiptsBox;
    final links = _repo.linksBox;
    return Scaffold(
      appBar: AppBar(title: const Text('Settle with adjustment')),
      body: (receipts == null || links == null)
          ? const Center(child: Text('Settlements are not available.'))
          : AnimatedBuilder(
              animation: Listenable.merge(
                  [receipts.listenable(), links.listenable()]),
              builder: (context, _) => _content(context),
            ),
    );
  }

  Widget _content(BuildContext context) {
    final symbol = context.read<AppStateController>().settings.currencySymbol;
    final money = NumberFormat('#,##0.00');
    String fmt(int minor) => '$symbol${money.format(minor / 100)}';
    final dayFmt = DateFormat('d MMM yyyy');
    final q = _search.text.trim().toLowerCase();

    final open = [
      for (final b in _repo.openBalances())
        if (q.isEmpty ||
            b.sale.receiptCode.toLowerCase().contains(q) ||
            b.sale.customerName.toLowerCase().contains(q))
          b,
    ];
    final records = _repo.writeoffs();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Use this when a customer settles for slightly less than they owe. '
              'The amount you write off is taken off the balance owed. No cash '
              'moves, the receipt is never changed, and reports show it as a '
              'settlement adjustment. A reason is required, and you can void it later.',
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Search by receipt number or customer',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Text('Balances owed (${open.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (open.isEmpty)
          const Card(child: ListTile(title: Text('No balances owed')))
        else
          Card(
            child: Column(
              children: [
                for (final b in open)
                  ListTile(
                    title: Text(b.sale.receiptCode),
                    subtitle: Text([
                      dayFmt.format(b.sale.issuedAt),
                      if (b.sale.customerName.isNotEmpty) b.sale.customerName,
                      'Owes ${fmt(b.outstandingMinor)}',
                    ].join(' · ')),
                    trailing: TextButton(
                      onPressed: () => _settle(context, b, fmt),
                      child: const Text('Settle'),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Text('Settlement adjustments (${records.length})',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        if (records.isEmpty)
          const Card(child: ListTile(title: Text('None yet')))
        else
          Card(
            child: Column(
              children: [
                for (final r in records) _recordTile(context, r, fmt, dayFmt),
              ],
            ),
          ),
      ],
    );
  }

  Widget _recordTile(BuildContext context, ReceiptLink r,
      String Function(int) fmt, DateFormat dayFmt) {
    final voided = r.voidedAt != null;
    final struck = voided
        ? const TextStyle(decoration: TextDecoration.lineThrough)
        : null;
    return ListTile(
      title: Text('${r.receiptCode}  ·  ${fmt(BalanceMath.toMinor(r.amount))}',
          style: struck),
      subtitle: Text([
        dayFmt.format(r.createdAt),
        r.reason,
        if (voided) 'Voided: ${r.voidReason ?? ''}',
      ].join(' · ')),
      isThreeLine: voided,
      trailing: voided
          ? null
          : TextButton(
              onPressed: () => _void(context, r),
              child: const Text('Void'),
            ),
    );
  }

  Future<void> _settle(BuildContext context, OpenBalance b,
      String Function(int) fmt) async {
    final amountCtrl = TextEditingController(
        text: (b.outstandingMinor / 100).toStringAsFixed(2));
    final reasonCtrl = TextEditingController();
    String? error;
    var saving = false;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Settle ${b.sale.receiptCode}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Balance owed: ${fmt(b.outstandingMinor)}'),
                const SizedBox(height: 4),
                const Text(
                    'Enter the amount to write off. Any balance left after it stays owed.'),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Amount to write off'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  textCapitalization: TextCapitalization.sentences,
                  decoration:
                      const InputDecoration(labelText: 'Reason (required)'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Text(error!,
                      style:
                          TextStyle(color: Theme.of(ctx).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final amount = double.tryParse(
                          amountCtrl.text.trim().replaceAll(',', ''));
                      if (amount == null) {
                        setLocal(() => error = 'Enter a valid amount.');
                        return;
                      }
                      setLocal(() {
                        saving = true;
                        error = null;
                      });
                      String? result;
                      try {
                        result = await _repo.writeOff(
                          receiptCode: b.sale.receiptCode,
                          amount: amount,
                          reason: reasonCtrl.text,
                        );
                      } catch (_) {
                        result = 'Could not save. Please try again.';
                      }
                      if (result == null) {
                        if (ctx.mounted) Navigator.of(ctx).pop(true);
                      } else {
                        setLocal(() {
                          saving = false;
                          error = result;
                        });
                      }
                    },
              child: const Text('Write off'),
            ),
          ],
        ),
      ),
    );
    amountCtrl.dispose();
    reasonCtrl.dispose();
    if (done == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Settlement saved.')));
    }
  }

  Future<void> _void(BuildContext context, ReceiptLink r) async {
    final reasonCtrl = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Void settlement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'The record stays, but the written-off amount is owed again. This cannot be undone.'),
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
                  result = await _repo.voidWriteoff(r.id, reasonCtrl.text);
                } catch (_) {
                  result = 'Could not void. Please try again.';
                }
                if (result == null) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } else {
                  setLocal(() => error = result);
                }
              },
              child: const Text('Void settlement'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }
}
