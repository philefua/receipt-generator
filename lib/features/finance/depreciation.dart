/// Pure depreciation maths for fixed assets (handoff 6A). No Hive, no Flutter,
/// so it is easy to test and the report engine can reuse it.
///
/// Depreciation is computed from the asset register for any period and is
/// never typed in or stored. All money is whole minor units (amount x 100),
/// like BalanceMath, so totals never drift.
///
/// Monthly convention: the first charge is in the month of purchase, as a
/// full month. A retired asset is charged up to and including its retirement
/// month, and nothing after.
class AssetSpec {
  final DateTime purchaseDate;
  final int costMinor;
  final int residualMinor;
  final int usefulLifeMonths;
  final bool reducingBalance;

  /// Annual rate in percent. Reducing balance only.
  final double annualRatePercent;
  final DateTime? retiredDate;
  final int proceedsMinor;

  /// Voided assets are left out of every total.
  final bool voided;

  const AssetSpec({
    required this.purchaseDate,
    required this.costMinor,
    this.residualMinor = 0,
    required this.usefulLifeMonths,
    this.reducingBalance = false,
    this.annualRatePercent = 0,
    this.retiredDate,
    this.proceedsMinor = 0,
    this.voided = false,
  });

  AssetSpec withRetirement(DateTime date, int proceeds) => AssetSpec(
        purchaseDate: purchaseDate,
        costMinor: costMinor,
        residualMinor: residualMinor,
        usefulLifeMonths: usefulLifeMonths,
        reducingBalance: reducingBalance,
        annualRatePercent: annualRatePercent,
        retiredDate: date,
        proceedsMinor: proceeds,
        voided: voided,
      );
}

/// What happened when an asset was retired.
class Disposal {
  /// Net book value after the retirement month's charge.
  final int nbvMinor;
  final int proceedsMinor;

  const Disposal({required this.nbvMinor, required this.proceedsMinor});

  /// Proceeds minus net book value. Negative is a loss; with no proceeds it is
  /// a write-off loss equal to the net book value.
  int get gainLossMinor => proceedsMinor - nbvMinor;
}

class Depreciation {
  Depreciation._();

  /// Months counted from year 0, so two dates compare by calendar month.
  static int monthIndex(DateTime d) => d.year * 12 + (d.month - 1);

  /// Depreciation built up through the month of [asOf] (inclusive).
  ///
  /// Straight line: (cost - residual) x months / life, rounded on the running
  /// total, so the last month lands exactly on cost - residual.
  /// Reducing balance: each month takes opening net book value x rate / 12,
  /// never taking net book value below residual.
  static int accumulated(AssetSpec a, DateTime asOf) {
    final start = monthIndex(a.purchaseDate);
    var last = monthIndex(asOf);
    if (a.retiredDate != null) {
      final r = monthIndex(a.retiredDate!);
      if (r < last) last = r;
    }
    if (last < start) return 0;
    final months = last - start + 1;
    final base = a.costMinor - a.residualMinor;
    if (base <= 0) return 0;

    if (!a.reducingBalance) {
      if (a.usefulLifeMonths <= 0) return 0;
      final m = months > a.usefulLifeMonths ? a.usefulLifeMonths : months;
      final life = a.usefulLifeMonths;
      // Half-up integer rounding of base * m / life.
      return (2 * base * m + life) ~/ (2 * life);
    }

    var nbv = a.costMinor;
    var acc = 0;
    for (var i = 0; i < months; i++) {
      var charge = (nbv * a.annualRatePercent / 1200).round();
      if (nbv - charge < a.residualMinor) charge = nbv - a.residualMinor;
      if (charge <= 0) break;
      nbv -= charge;
      acc += charge;
    }
    return acc;
  }

  /// Cost less depreciation to date, never below residual.
  static int netBookValue(AssetSpec a, DateTime asOf) =>
      a.costMinor - accumulated(a, asOf);

  /// Charge for the whole months from [from]'s month to [to]'s month,
  /// inclusive. Months outside the asset's life are free of charge.
  static int charge(AssetSpec a, DateTime from, DateTime to) {
    if (monthIndex(to) < monthIndex(from)) return 0;
    final before = DateTime(from.year, from.month - 1, 1);
    return accumulated(a, to) - accumulated(a, before);
  }

  /// Gain or loss on retirement, or null if the asset is not retired.
  static Disposal? disposal(AssetSpec a) {
    final r = a.retiredDate;
    if (r == null) return null;
    return Disposal(
      nbvMinor: netBookValue(a, r),
      proceedsMinor: a.proceedsMinor,
    );
  }

  /// True if the asset was retired in a month inside [from]..[to].
  static bool retiredWithin(AssetSpec a, DateTime from, DateTime to) {
    final r = a.retiredDate;
    if (r == null) return false;
    final i = monthIndex(r);
    return i >= monthIndex(from) && i <= monthIndex(to);
  }

  /// Total charge for several assets. Voided assets are skipped.
  static int totalCharge(Iterable<AssetSpec> assets, DateTime from, DateTime to) {
    var sum = 0;
    for (final a in assets) {
      if (a.voided) continue;
      sum += charge(a, from, to);
    }
    return sum;
  }
}
