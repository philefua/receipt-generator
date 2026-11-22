import 'models/expense.dart';

/// Totals for one period, in integer minor units (amount x 100) so sums never
/// drift. Voided expenses are never counted. Not-in-P&L money (drawings, tax
/// remittances) is kept apart and is not part of [totalExpensesMinor].
class ExpenseTotals {
  final int directMinor;
  final int operatingMinor;
  final int notInPnlMinor;
  final int count;

  const ExpenseTotals({
    this.directMinor = 0,
    this.operatingMinor = 0,
    this.notInPnlMinor = 0,
    this.count = 0,
  });

  /// Direct plus operating. Excludes Not in P&L.
  int get totalExpensesMinor => directMinor + operatingMinor;

  double get direct => directMinor / 100;
  double get operating => operatingMinor / 100;
  double get notInPnl => notInPnlMinor / 100;
  double get totalExpenses => totalExpensesMinor / 100;
}

int toMinor(double amount) => (amount * 100).round();

ExpenseTotals computeTotals(Iterable<Expense> expenses) {
  var direct = 0, operating = 0, notInPnl = 0, count = 0;
  for (final e in expenses) {
    if (e.isVoided) continue;
    count++;
    final m = toMinor(e.amount);
    switch (e.categoryType) {
      case 'direct':
        direct += m;
      case 'operating':
        operating += m;
      default:
        notInPnl += m;
    }
  }
  return ExpenseTotals(
    directMinor: direct,
    operatingMinor: operating,
    notInPnlMinor: notInPnl,
    count: count,
  );
}

/// Totals per calendar month, keyed by the first day of the month, newest first.
List<MapEntry<DateTime, ExpenseTotals>> totalsByMonth(Iterable<Expense> expenses) {
  final groups = <DateTime, List<Expense>>{};
  for (final e in expenses) {
    final key = DateTime(e.date.year, e.date.month);
    groups.putIfAbsent(key, () => []).add(e);
  }
  final keys = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final k in keys) MapEntry(k, computeTotals(groups[k]!))];
}
