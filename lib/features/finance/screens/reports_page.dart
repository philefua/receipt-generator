import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../state/app_state_controller.dart';
import '../finance_repository.dart';
import '../report_adapter.dart';
import '../report_data.dart';
import '../report_engine.dart';
import '../report_period.dart';
import '../report_workbook.dart';

enum _PeriodChoice {
  thisMonth,
  lastMonth,
  thisQuarter,
  thisFinancialYear,
  lastFinancialYear,
  custom,
}

/// Manager-only: pick a period, preview the headline figures, then build the
/// Excel financial report and share it. Reached from the Finance card in the
/// Manager Backend, behind the password.
class ManagerReportsPage extends StatefulWidget {
  const ManagerReportsPage({super.key});

  @override
  State<ManagerReportsPage> createState() => _ManagerReportsPageState();
}

class _ManagerReportsPageState extends State<ManagerReportsPage> {
  _PeriodChoice _choice = _PeriodChoice.thisMonth;
  DateTimeRange? _customRange;
  ReportData? _data;
  bool _building = false;
  bool _sharing = false;
  String? _error;

  static final DateFormat _dateFmt = DateFormat('d MMM yyyy');
  static final NumberFormat _moneyFmt = NumberFormat('#,##0.00');

  int get _startMonth {
    try {
      final m = FinanceRepository.instance.settings.financialYearStartMonth;
      return m < 1 ? 1 : (m > 12 ? 12 : m);
    } catch (_) {
      return 1;
    }
  }

  ReportPeriod _period() {
    final today = DateTime.now();
    switch (_choice) {
      case _PeriodChoice.thisMonth:
        return ReportPeriod.thisMonth(today);
      case _PeriodChoice.lastMonth:
        return ReportPeriod.lastMonth(today);
      case _PeriodChoice.thisQuarter:
        return ReportPeriod.thisQuarter(today, _startMonth);
      case _PeriodChoice.thisFinancialYear:
        return ReportPeriod.thisFinancialYear(today, _startMonth);
      case _PeriodChoice.lastFinancialYear:
        return ReportPeriod.lastFinancialYear(today, _startMonth);
      case _PeriodChoice.custom:
        final r = _customRange;
        if (r == null) return ReportPeriod.thisMonth(today);
        return ReportPeriod.custom(r.start, r.end);
    }
  }

  String _choiceLabel(_PeriodChoice c) {
    switch (c) {
      case _PeriodChoice.thisMonth:
        return 'This month';
      case _PeriodChoice.lastMonth:
        return 'Last month';
      case _PeriodChoice.thisQuarter:
        return 'This quarter';
      case _PeriodChoice.thisFinancialYear:
        return 'This financial year';
      case _PeriodChoice.lastFinancialYear:
        return 'Last financial year';
      case _PeriodChoice.custom:
        return 'Custom dates';
    }
  }

  Future<void> _selectChoice(_PeriodChoice c) async {
    if (c == _PeriodChoice.custom) {
      final now = DateTime.now();
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: _customRange ??
            DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: DateTime(now.year, now.month, now.day),
            ),
      );
      if (picked == null || !mounted) return;
      setState(() {
        _choice = c;
        _customRange = picked;
        _data = null;
        _error = null;
      });
      return;
    }
    setState(() {
      _choice = c;
      _data = null;
      _error = null;
    });
  }

  Future<void> _build() async {
    setState(() {
      _building = true;
      _error = null;
      _data = null;
    });
    // Let the spinner paint before the (synchronous) report work starts.
    await Future<void>.delayed(const Duration(milliseconds: 30));
    try {
      final input = ReportAdapter.fromHive();
      final data = ReportEngine.generate(
        input,
        _period(),
        generatedAt: DateTime.now(),
      );
      if (!mounted) return;
      setState(() => _data = data);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not build the report: $e');
    } finally {
      if (mounted) setState(() => _building = false);
    }
  }

  Future<void> _share() async {
    final data = _data;
    if (data == null) return;
    final settings = context.read<AppStateController>().settings;
    setState(() => _sharing = true);
    try {
      final bytes = ReportWorkbook.build(
        data,
        businessName: settings.businessName,
        address: settings.address,
        phone: settings.phone,
        currencySymbol: settings.currencySymbol,
      );
      // Same simple style as the history export's file name (no hyphens).
      final fileName = ReportWorkbook.fileName(data).replaceAll('-', '');

      final directory = await getApplicationDocumentsDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);

      if (!mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath, name: fileName)],
          text: 'Financial report ($fileName)',
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Report ready. Choose "Save to Downloads" or your preferred app.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _money(int minor, String symbol) =>
      '$symbol${_moneyFmt.format(minor / 100)}';

  @override
  Widget build(BuildContext context) {
    final ready = FinanceRepository.instance.isReady;
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: !ready
          ? const Center(child: Text('Reports are not available on this device.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Period', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in _PeriodChoice.values)
                      ChoiceChip(
                        label: Text(_choiceLabel(c)),
                        selected: _choice == c,
                        onSelected: (_building || _sharing)
                            ? null
                            : (_) => _selectChoice(c),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${_dateFmt.format(_period().from)} to ${_dateFmt.format(_period().to)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: (_building || _sharing) ? null : _build,
                  icon: _building
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.assessment_outlined),
                  label: Text(_building ? 'Building...' : 'Build report'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!),
                    ),
                  ),
                ],
                if (_data != null) ..._reportSection(context, _data!),
              ],
            ),
    );
  }

  List<Widget> _reportSection(BuildContext context, ReportData d) {
    final symbol = context.read<AppStateController>().settings.currencySymbol;
    final s = d.summary;
    final textTheme = Theme.of(context).textTheme;

    Widget row(String label, int minor, {bool bold = false}) {
      final style = bold
          ? textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)
          : textTheme.bodyMedium;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label, style: style)),
            Text(_money(minor, symbol), style: style),
          ],
        ),
      );
    }

    return [
      const SizedBox(height: 16),
      if (s.unmatchedCount > 0)
        Card(
          color: Theme.of(context).colorScheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              '${s.unmatchedCount} balance payment(s) could not be matched to a '
              'sale. They are listed on their own sheet in the file. Link them '
              'under Finance > Unmatched balance payments for a complete report.',
            ),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(d.periodLabel, style: textTheme.titleMedium),
              const SizedBox(height: 8),
              row('Total sales', s.totalSalesMinor),
              row('Total expenses', s.totalExpensesMinor),
              row('Gross profit', s.grossProfitMinor),
              row('Net profit before tax', s.netProfitMinor, bold: true),
              row('Estimated tax', s.estimatedTaxMinor),
              row('Net profit after tax', s.netProfitAfterTaxMinor, bold: true),
              const Divider(),
              row('Cash in', s.cashInMinor),
              row('Cash out', s.cashOutMinor),
              row('Net cash movement', s.cashNetMinor, bold: true),
              const Divider(),
              row('Receivables (owed to you)', s.receivablesMinor),
              row('Fixed assets (net book value)', s.assetNetBookValueMinor),
              row('Loans outstanding', s.loansOutstandingMinor),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: (_building || _sharing) ? null : _share,
        icon: _sharing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.share_outlined),
        label: Text(_sharing ? 'Preparing file...' : 'Share Excel file'),
      ),
      const SizedBox(height: 8),
      Text(
        'Some phone previewers show formula cells blank. Open the file in '
        'Excel or Google Sheets to see every figure.',
        style: textTheme.bodySmall,
      ),
    ];
  }
}
