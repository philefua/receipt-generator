import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/app_state_controller.dart';
import '../legacy_balance_resolver.dart';
import '../legacy_link_repository.dart';

/// Manager-only: old balance receipts (typed text, made before balance
/// payments existed) that could not be linked automatically. Reached from the
/// Finance card in the Manager Backend, behind the password.
class UnmatchedBalancePaymentsPage extends StatelessWidget {
  const UnmatchedBalancePaymentsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = LegacyLinkRepository.instance;
    final receipts = repo.receiptsBox;
    final links = repo.linksBox;
    return Scaffold(
      appBar: AppBar(title: const Text('Unmatched balance payments')),
      body: (receipts == null || links == null)
          ? const Center(child: Text('Balance links are not available.'))
          : AnimatedBuilder(
              animation: Listenable.merge(
                  [receipts.listenable(), links.listenable()]),
              builder: (context, _) => _Content(repo: repo),
            ),
    );
  }
}

class _Money {
  final String symbol;
  final NumberFormat _f = NumberFormat('#,##0.00');
  _Money(this.symbol);
  String minor(int v) => '$symbol${_f.format(v / 100)}';
}

class _Content extends StatelessWidget {
  final LegacyLinkRepository repo;
  const _Content({required this.repo});

  @override
  Widget build(BuildContext context) {
    final symbol = context.read<AppStateController>().settings.currencySymbol;
    final money = _Money(symbol);
    final dayFmt = DateFormat('d MMM yyyy');

    final resolution = repo.resolve();
    final review = resolution.needsReview;
    final linked = resolution.linked;
    final auto =
        linked.where((e) => e.status == LegacyStatus.linkedAuto).length;
    final manual = linked.length - auto;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.isEmpty
                      ? 'Nothing needs attention'
                      : '${review.length} need${review.length == 1 ? 's' : ''} your attention',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Old receipts that were typed by hand as balance payments. '
                  'Clean matches are linked automatically ($auto so far). '
                  '$manual linked by you. Nothing on a receipt is ever changed: '
                  'a link is kept beside it.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final e in review)
          _ReviewCard(
            entry: e,
            money: money,
            dayFmt: dayFmt,
            onLink: (code) =>
                _openDialog(context, resolution, e, money, code),
          ),
        if (linked.isNotEmpty) ...[
          const SizedBox(height: 4),
          Card(
            child: ExpansionTile(
              title: Text('Linked (${linked.length})'),
              children: [
                for (final e in linked)
                  _LinkedTile(
                    entry: e,
                    money: money,
                    repo: repo,
                    onChange: () =>
                        _openDialog(context, resolution, e, money, e.originalCode),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _openDialog(BuildContext context, LegacyResolution resolution,
      LegacyBalanceEntry entry, _Money money, String? initialCode) async {
    final byCode = {for (final r in repo.records()) r.code: r};
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _LinkDialog(
        repo: repo,
        entry: entry,
        resolution: resolution,
        byCode: byCode,
        money: money,
        initialCode: initialCode ?? '',
      ),
    );
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Link saved.')));
    }
  }
}

class _ReviewCard extends StatelessWidget {
  final LegacyBalanceEntry entry;
  final _Money money;
  final DateFormat dayFmt;
  final void Function(String? code) onLink;

  const _ReviewCard({
    required this.entry,
    required this.money,
    required this.dayFmt,
    required this.onLink,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = entry;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.code, style: theme.textTheme.titleMedium),
                Text(money.minor(e.paidMinor),
                    style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 4),
            Text([
              dayFmt.format(e.issuedAt),
              if (e.customerName.isNotEmpty) e.customerName,
              'Paid on this receipt',
            ].join(' · ')),
            const SizedBox(height: 8),
            Text(e.reason?.label ?? '',
                style: TextStyle(color: theme.colorScheme.error)),
            if (e.textSnippet.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Written on the receipt: ${e.textSnippet}',
                  style: theme.textTheme.bodySmall),
            ],
            if (e.originalCode != null) ...[
              const SizedBox(height: 4),
              Text(
                'Points to ${e.originalCode}'
                '${e.suggestedAppliedMinor != null ? ' (${money.minor(e.suggestedAppliedMinor!)} still owed)' : ''}',
              ),
            ],
            if (e.suggestions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Possible matches', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final s in e.suggestions)
                    Tooltip(
                      message: s.reasons.join('\n'),
                      child: ActionChip(
                        label: Text(
                            '${s.code} · ${s.customerName.isEmpty ? 'no name' : s.customerName} · owes ${money.minor(s.outstandingMinor)}'),
                        onPressed: () => onLink(s.code),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => onLink(e.originalCode),
                child: const Text('Link to original sale'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkedTile extends StatelessWidget {
  final LegacyBalanceEntry entry;
  final _Money money;
  final LegacyLinkRepository repo;
  final VoidCallback onChange;

  const _LinkedTile({
    required this.entry,
    required this.money,
    required this.repo,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final isManual = e.status == LegacyStatus.linkedManual;
    final note = isManual && e.manualLinkId != null
        ? repo.noteFor(e.manualLinkId!)
        : null;
    return ListTile(
      title: Text('${e.code}  →  ${e.originalCode ?? ''}'),
      subtitle: Text([
        '${money.minor(e.appliedMinor)} applied',
        isManual ? 'linked by you' : 'automatic',
        if (note != null) note,
      ].join(' · ')),
      trailing: isManual
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: onChange, child: const Text('Change')),
                TextButton(
                  onPressed: () => _void(context, e.manualLinkId!),
                  child: const Text('Void'),
                ),
              ],
            )
          : TextButton(onPressed: onChange, child: const Text('Change')),
    );
  }

  Future<void> _void(BuildContext context, String linkId) async {
    final reasonCtrl = TextEditingController();
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Void link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'The link stays on record but no longer counts. The receipt goes back to its automatic result.'),
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
                  result = await repo.voidLink(linkId, reasonCtrl.text);
                } catch (_) {
                  result = 'Could not void the link. Please try again.';
                }
                if (result == null) {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                } else {
                  setLocal(() => error = result);
                }
              },
              child: const Text('Void link'),
            ),
          ],
        ),
      ),
    );
    reasonCtrl.dispose();
  }
}

class _LinkDialog extends StatefulWidget {
  final LegacyLinkRepository repo;
  final LegacyBalanceEntry entry;
  final LegacyResolution resolution;
  final Map<String, LegacyReceiptRecord> byCode;
  final _Money money;
  final String initialCode;

  const _LinkDialog({
    required this.repo,
    required this.entry,
    required this.resolution,
    required this.byCode,
    required this.money,
    required this.initialCode,
  });

  @override
  State<_LinkDialog> createState() => _LinkDialogState();
}

class _LinkDialogState extends State<_LinkDialog> {
  late final TextEditingController _code;
  late final TextEditingController _amount;
  final _note = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _code = TextEditingController(text: widget.initialCode);
    // Default to what was actually received, or the remaining balance when
    // the receipt paid more than the original still owed.
    final start = e.isLinked
        ? e.appliedMinor
        : (e.suggestedAppliedMinor ?? e.paidMinor);
    _amount = TextEditingController(
        text: start > 0 ? (start / 100).toStringAsFixed(2) : '');
  }

  @override
  void dispose() {
    _code.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _preview() {
    final code = _code.text.trim();
    if (code.isEmpty) return null;
    final r = widget.byCode[code];
    if (r == null) return 'No receipt with this number (capital and small letters matter).';
    if (r.isBalanceType) return 'This is a balance receipt, not the original sale.';
    final owed = widget.resolution.remainingExcluding(code, widget.entry.code);
    return '${r.customerName.isEmpty ? 'No name' : r.customerName} · '
        'total ${widget.money.minor(r.totalMinor)} · '
        'still owed ${widget.money.minor(owed)}';
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (amount == null) {
      setState(() => _error = 'Enter a valid amount.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    String? result;
    try {
      result = await widget.repo.saveManualLink(
        legacyCode: widget.entry.code,
        originalCode: _code.text,
        amount: amount,
        note: _note.text,
      );
    } catch (_) {
      result = 'Could not save the link. Please try again.';
    }
    if (!mounted) return;
    if (result == null) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final preview = _preview();
    return AlertDialog(
      title: Text('Link ${e.code}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Money received on this receipt: ${widget.money.minor(e.paidMinor)}'),
            if (e.reason == ReviewReason.mixedReceipt) ...[
              const SizedBox(height: 4),
              const Text(
                  'This receipt also sold new items. Enter only the part that paid the old balance.'),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              onChanged: (_) => setState(() {}),
              autocorrect: false,
              decoration: const InputDecoration(
                  labelText: 'Original sale receipt number'),
            ),
            if (preview != null) ...[
              const SizedBox(height: 4),
              Text(preview, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Amount applied to the old balance'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: _saving ? null : _save, child: const Text('Save link')),
      ],
    );
  }
}
