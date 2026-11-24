/// Pure checks for the asset forms (handoff 6A). No Hive, no Flutter.
class AssetRules {
  AssetRules._();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Plain-English problem with a new asset, or null if it is fine.
  /// Past purchase dates are allowed: equipment bought before the shop used
  /// the app is entered with its original date and cost.
  static String? validateNew({
    required String name,
    required DateTime purchaseDate,
    required DateTime today,
    required double cost,
    required double residual,
    required int? usefulLifeMonths,
    required bool reducingBalance,
    required double? annualRatePercent,
  }) {
    if (name.trim().isEmpty) return 'Enter the asset name.';
    if (_day(purchaseDate).isAfter(_day(today))) {
      return 'The purchase date cannot be in the future.';
    }
    if (purchaseDate.year < 1990) return 'Check the purchase date.';
    if (cost.isNaN || cost.isInfinite || cost <= 0) {
      return 'Enter a cost above zero.';
    }
    if (residual.isNaN || residual.isInfinite || residual < 0) {
      return 'The residual value cannot be negative.';
    }
    if (residual >= cost) {
      return 'The residual value must be less than the cost.';
    }
    if (usefulLifeMonths == null || usefulLifeMonths < 1) {
      return 'Enter the useful life in months (at least 1).';
    }
    if (usefulLifeMonths > 1200) {
      return 'The useful life cannot be more than 1200 months.';
    }
    if (reducingBalance) {
      final r = annualRatePercent;
      if (r == null || r.isNaN || r <= 0 || r > 100) {
        return 'Enter an annual rate between 0 and 100 percent.';
      }
    }
    return null;
  }

  /// Plain-English problem with retiring an asset, or null if it is fine.
  static String? validateRetire({
    required bool isActive,
    required bool isVoided,
    required DateTime purchaseDate,
    required DateTime retireDate,
    required DateTime today,
    double? proceeds,
  }) {
    if (isVoided) return 'This asset is voided.';
    if (!isActive) return 'This asset is already retired.';
    if (_day(retireDate).isBefore(_day(purchaseDate))) {
      return 'The retirement date cannot be before the purchase date.';
    }
    if (_day(retireDate).isAfter(_day(today))) {
      return 'The retirement date cannot be in the future.';
    }
    if (proceeds != null &&
        (proceeds.isNaN || proceeds.isInfinite || proceeds < 0)) {
      return 'Sale proceeds cannot be negative.';
    }
    return null;
  }

  static String? validateVoid({required String reason, required bool isVoided}) {
    if (isVoided) return 'This asset is already voided.';
    if (reason.trim().isEmpty) return 'Enter a reason for voiding.';
    return null;
  }

  /// True when the form should suggest recording an expense instead. Off when
  /// the threshold is 0, and never for equipment already owned.
  static bool belowThreshold({
    required double cost,
    required double threshold,
    required bool isOpeningBalance,
  }) =>
      !isOpeningBalance && threshold > 0 && cost > 0 && cost < threshold;
}
