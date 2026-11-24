import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state_controller.dart';
import '../asset_repository.dart';
import '../depreciation.dart';
import '../models/asset.dart';
import '../widgets/asset_form.dart';

/// Manager-only: the fixed-asset register with net book values, add, retire
/// and void. Reached from the Finance card in the Manager Backend, behind the
/// password. Depreciation is computed here from the register and never stored.
class ManagerAssetsPage extends StatelessWidget {
  const ManagerAssetsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = AssetRepository.instance;
    final box = repo.box;
    return Scaffold(
      appBar: AppBar(title: const Text('Assets')),
      floatingActionButton: box == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAdd(context),
              icon: const Icon(Icons.add),
              label: const Text('Add asset'),
            ),
      body: box == null
          ? const Center(child: Text('Assets are not available.'))
          : ValueListenableBuilder<Box<Asset>>(
              valueListenable: box.listenable(),
              builder: (context, _, child) => _content(context),
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
              Text('Add asset', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              AssetForm(onSaved: () => Navigator.of(ctx).pop()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final repo = AssetRepository.instance;
    final symbol = context.read<AppStateController>().settings.currencySymbol;
    final money = NumberFormat('#,##0.00');
    String fmt(int minor) => '$symbol${money.format(minor / 100)}';
    final dayFmt = DateFormat('d MMM yyyy');
    final now = DateTime.now();

    final assets = repo.all();
    final totals = repo.totals(asOf: now);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Active assets (${totals.count})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _row('Total cost', fmt(totals.costMinor)),
                _row('Total net book value', fmt(totals.nbvMinor), bold: true),
                const SizedBox(height: 4),
                Text(
                  'Net book value is cost less depreciation to today. Retired '
                  'and voided assets are not counted. Depreciation is worked '
                  'out from this list and is never typed in.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (assets.isEmpty)
          const Card(child: ListTile(title: Text('No assets yet')))
        else
          Card(
            child: Column(
              children: [
                for (final a in assets) _tile(context, a, fmt, dayFmt, now),
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

  Widget _tile(BuildContext context, Asset a, String Function(int) fmt,
      DateFormat dayFmt, DateTime now) {
    final repo = AssetRepository.instance;
    final spec = AssetRepository.specOf(a);
    final voided = a.voidedAt != null;
    final retired = a.status == Asset.statusRetired;
    final struck =
        voided ? const TextStyle(decoration: TextDecoration.lineThrough) : null;
    final nbv = Depreciation.netBookValue(spec, now);
    return ListTile(
      title: Text(a.name, style: struck),
      subtitle: Text([
        repo.categoryName(a.categoryId),
        dayFmt.format(a.purchaseDate),
        if (a.isOpeningBalance) 'Opening balance',
        if (retired) 'Retired',
        if (voided) 'Voided',
      ].join(' · ')),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(fmt(spec.costMinor), style: struck),
          if (!voided)
            Text(retired ? 'Retired' : 'NBV ${fmt(nbv)}',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      onTap: () => _showDetail(context, a, fmt, dayFmt, now),
    );
  }

  Future<void> _showDetail(BuildContext context, Asset a,
      String Function(int) fmt, DateFormat dayFmt, DateTime now) async {
    final repo = AssetRepository.instance;
    final spec = AssetRepository.specOf(a);
    final when = DateFormat('d MMM yyyy, HH:mm');
    final accumulated = Depreciation.accumulated(spec, now);
    final thisMonth = Depreciation.charge(spec, now, now);
    final disposal = Depreciation.disposal(spec);
    final reducing = a.method == Asset.methodReducingBalance;

    Widget line(String k, String? v) => (v == null || v.isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('$k: $v'),
          );

    String gainLoss(int minor) =>
        minor < 0 ? 'Loss of ${fmt(-minor)}' : 'Gain of ${fmt(minor)}';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(a.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              line('Category', repo.categoryName(a.categoryId)),
              line('Purchase date', dayFmt.format(a.purchaseDate)),
              line('Cost', fmt(spec.costMinor)),
              line('Residual value', fmt(spec.residualMinor)),
              line('Useful life', '${a.usefulLifeMonths} months'),
              line('Method',
                  reducing ? 'Reducing balance, ${a.annualRate ?? 0}% a year' : 'Straight-line'),
              line('Paid from', a.paymentMethod),
              line('Vendor', a.vendor),
              line('Notes', a.notes),
              const Divider(),
              line('Depreciation to date', fmt(accumulated)),
              line('Net book value', fmt(Depreciation.netBookValue(spec, now))),
              if (a.status == Asset.statusActive && a.voidedAt == null)
                line('This month\'s charge', fmt(thisMonth)),
              if (disposal != null) ...[
                const Divider(),
                line('Retired', dayFmt.format(a.retiredDate!)),
                line('Sale proceeds', fmt(disposal.proceedsMinor)),
                line('Net book value at retirement', fmt(disposal.nbvMinor)),
                line('Result', gainLoss(disposal.gainLossMinor)),
              ],
              const Divider(),
              line('Entered', when.format(a.createdAt)),
              if (a.voidedAt != null) ...[
                line('Voided', when.format(a.voidedAt!)),
                line('Reason', a.voidReason),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close')),
          if (a.status == Asset.statusActive && a.voidedAt == null)
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _showRetire(context, a, fmt);
              },
              child: const Text('Retire'),
            ),
          if (a.voidedAt == null)
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _showVoid(context, a);
              },
              child: const Text('Void'),
            ),
        ],
      ),
    );
  }

  Future<void> _showRetire(
      BuildContext context, Asset a, String Function(int) fmt) async {
    final repo = AssetRepository.instance;
    final proceedsCtrl = TextEditingController();
    final today = AssetRepository.dateOnly(DateTime.now());
    var date = today;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final proceeds =
              double.tryParse(proceedsCtrl.text.replaceAll(',', '').trim()) ?? 0;
          final preview = repo.previewRetirement(a, date, proceeds);
          return AlertDialog(
            title: Text('Retire ${a.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'Retire an asset that was sold, scrapped or lost. Depreciation stops after the retirement month. This cannot be undone; to correct a mistake, void it and enter it again.'),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: date,
                        firstDate: a.purchaseDate,
                        lastDate: today,
                      );
                      if (picked != null) {
                        setLocal(() => date = AssetRepository.dateOnly(picked));
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Retirement date',
                          suffixIcon: Icon(Icons.calendar_today_outlined)),
                      child: Text(DateFormat('EEE, d MMM yyyy').format(date)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: proceedsCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setLocal(() {}),
                    decoration: const InputDecoration(
                        labelText: 'Sale proceeds (optional)'),
                  ),
                  if (preview != null) ...[
                    const SizedBox(height: 12),
                    Text('Net book value at retirement: ${fmt(preview.nbvMinor)}'),
                    Text(preview.gainLossMinor < 0
                        ? 'Loss of ${fmt(-preview.gainLossMinor)}'
                        : 'Gain of ${fmt(preview.gainLossMinor)}'),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!,
                        style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  final text = proceedsCtrl.text.replaceAll(',', '').trim();
                  final value = text.isEmpty ? null : double.tryParse(text);
                  if (text.isNotEmpty && value == null) {
                    setLocal(() => error = 'Enter a valid amount.');
                    return;
                  }
                  String? result;
                  try {
                    result = await repo.retireAsset(a, date, proceeds: value);
                  } catch (_) {
                    result = 'Could not retire the asset. Please try again.';
                  }
                  if (result == null) {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  } else {
                    setLocal(() => error = result);
                  }
                },
                child: const Text('Retire asset'),
              ),
            ],
          );
        },
      ),
    );
    proceedsCtrl.dispose();
  }

  Future<void> _showVoid(BuildContext context, Asset a) async {
    final reasonCtrl = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Void asset'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'The entry stays on record but is left out of totals and reports. This cannot be undone. To correct a mistake, void it and enter the asset again.'),
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
                  result =
                      await AssetRepository.instance.voidAsset(a, reasonCtrl.text);
                } catch (_) {
                  result = 'Could not void the asset. Please try again.';
                }
                if (result == null) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } else {
                  setLocal(() => error = result);
                }
              },
              child: const Text('Void asset'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }
}
