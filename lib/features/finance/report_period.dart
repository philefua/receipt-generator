/// A report period: whole days from [from] to [to], both included. Pure Dart.
///
/// The quick choices follow the shop's financial year. "This quarter" means a
/// three-month block counted from the first month of the financial year, so a
/// January start gives normal calendar quarters.
class ReportPeriod {
  final DateTime from;
  final DateTime to;
  final String label;

  ReportPeriod._(this.from, this.to, this.label);

  /// Any range. Times are dropped. The ends are swapped if given backwards.
  factory ReportPeriod.custom(DateTime a, DateTime b, {String label = 'Custom'}) {
    final x = _day(a);
    final y = _day(b);
    return x.isAfter(y) ? ReportPeriod._(y, x, label) : ReportPeriod._(x, y, label);
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Number of days covered, both ends included.
  int get days =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays +
      1;

  bool contains(DateTime d) {
    final x = _day(d);
    return !x.isBefore(from) && !x.isAfter(to);
  }

  /// The day before the period starts.
  DateTime get dayBefore => DateTime(from.year, from.month, from.day - 1);

  static ReportPeriod thisMonth(DateTime today) => ReportPeriod._(
        DateTime(today.year, today.month, 1),
        DateTime(today.year, today.month + 1, 0),
        'This month',
      );

  static ReportPeriod lastMonth(DateTime today) => ReportPeriod._(
        DateTime(today.year, today.month - 1, 1),
        DateTime(today.year, today.month, 0),
        'Last month',
      );

  /// First day of the financial year that contains [today].
  static DateTime financialYearStart(DateTime today, int startMonth) {
    final s = _clampMonth(startMonth);
    return today.month >= s
        ? DateTime(today.year, s, 1)
        : DateTime(today.year - 1, s, 1);
  }

  static ReportPeriod thisFinancialYear(DateTime today, int startMonth) {
    final start = financialYearStart(today, startMonth);
    return ReportPeriod._(
      start,
      DateTime(start.year + 1, start.month, 0),
      'This financial year',
    );
  }

  static ReportPeriod lastFinancialYear(DateTime today, int startMonth) {
    final start = financialYearStart(today, startMonth);
    final prev = DateTime(start.year - 1, start.month, 1);
    return ReportPeriod._(
      prev,
      DateTime(prev.year + 1, prev.month, 0),
      'Last financial year',
    );
  }

  static ReportPeriod thisQuarter(DateTime today, int startMonth) {
    final s = _clampMonth(startMonth);
    final fy = financialYearStart(today, s);
    final monthsIn = (today.month - s + 12) % 12;
    final q = monthsIn ~/ 3;
    final qs = DateTime(fy.year, fy.month + 3 * q, 1);
    return ReportPeriod._(
      qs,
      DateTime(qs.year, qs.month + 3, 0),
      'This quarter',
    );
  }

  static int _clampMonth(int m) => m < 1 ? 1 : (m > 12 ? 12 : m);

  @override
  String toString() => '$label: $from to $to';
}
