import 'package:hive/hive.dart';

import 'asset_rules.dart';
import 'balance_math.dart';
import 'depreciation.dart';
import 'finance_boxes.dart';
import 'finance_repository.dart';
import 'models/asset.dart';
import 'models/asset_category.dart';

/// Totals shown at the top of the Assets page. Active assets only: retired
/// and voided assets are left out.
class AssetTotals {
  final int count;
  final int costMinor;
  final int nbvMinor;
  const AssetTotals(
      {required this.count, required this.costMinor, required this.nbvMinor});
}

/// Reads and writes the asset register. Uses only the `hive` package.
/// Rules enforced here (not only in the screens):
///  - no edit and no delete after save; the only changes are retiring and voiding
///  - purchase date may be in the past (equipment owned before the app)
///  - equipment already owned records no cash outflow
class AssetRepository {
  AssetRepository._();
  static final AssetRepository instance = AssetRepository._();

  /// Stored as the payment method of equipment the shop already owned.
  static const String openingBalanceLabel = 'Opening balance';

  Box<Asset>? get box {
    try {
      return Hive.isBoxOpen(FinanceBoxes.assetsBox)
          ? Hive.box<Asset>(FinanceBoxes.assetsBox)
          : null;
    } catch (_) {
      return null;
    }
  }

  bool get isReady => box != null && FinanceRepository.instance.isReady;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static AssetSpec specOf(Asset a) => AssetSpec(
        purchaseDate: a.purchaseDate,
        costMinor: BalanceMath.toMinor(a.cost),
        residualMinor: BalanceMath.toMinor(a.residualValue),
        usefulLifeMonths: a.usefulLifeMonths,
        reducingBalance: a.method == Asset.methodReducingBalance,
        annualRatePercent: a.annualRate ?? 0,
        retiredDate: a.status == Asset.statusRetired ? a.retiredDate : null,
        proceedsMinor: BalanceMath.toMinor(a.disposalProceeds ?? 0),
        voided: a.voidedAt != null,
      );

  /// Active asset categories in display order.
  List<AssetCategory> categories({bool includeArchived = false}) {
    final b = FinanceRepository.instance.assetCategoryBox;
    if (b == null) return const [];
    return [
      for (final c in b.values)
        if (includeArchived || !c.archived) c,
    ]..sort((a, c) {
        final o = a.sortOrder.compareTo(c.sortOrder);
        return o != 0 ? o : a.name.toLowerCase().compareTo(c.name.toLowerCase());
      });
  }

  String categoryName(String id) =>
      FinanceRepository.instance.assetCategoryBox?.get(id)?.name ??
      'Unknown category';

  /// Every asset, newest purchase first. Voided ones are included.
  List<Asset> all() {
    final b = box;
    if (b == null) return const [];
    return b.values.toList()
      ..sort((a, c) {
        final d = c.purchaseDate.compareTo(a.purchaseDate);
        return d != 0 ? d : c.createdAt.compareTo(a.createdAt);
      });
  }

  AssetTotals totals({DateTime? asOf}) {
    final when = asOf ?? DateTime.now();
    var count = 0;
    var cost = 0;
    var nbv = 0;
    for (final a in all()) {
      if (a.voidedAt != null || a.status != Asset.statusActive) continue;
      final spec = specOf(a);
      count++;
      cost += spec.costMinor;
      nbv += Depreciation.netBookValue(spec, when);
    }
    return AssetTotals(count: count, costMinor: cost, nbvMinor: nbv);
  }

  /// Saves a new asset. Returns an error message, or null on success.
  Future<String?> addAsset({
    required String name,
    required String categoryId,
    required DateTime purchaseDate,
    required double cost,
    String paymentMethod = '',
    String? vendor,
    required int usefulLifeMonths,
    double residualValue = 0,
    String method = Asset.methodStraightLine,
    double? annualRate,
    bool isOpeningBalance = false,
    String notes = '',
    DateTime? now,
  }) async {
    final b = box;
    if (b == null) return 'Assets are not available on this device.';
    final catBox = FinanceRepository.instance.assetCategoryBox;
    if (catBox == null) return 'Categories are not available on this device.';

    final clock = now ?? DateTime.now();
    final reducing = method == Asset.methodReducingBalance;
    if (method != Asset.methodStraightLine && !reducing) {
      return 'Choose a depreciation method.';
    }

    final problem = AssetRules.validateNew(
      name: name,
      purchaseDate: purchaseDate,
      today: clock,
      cost: cost,
      residual: residualValue,
      usefulLifeMonths: usefulLifeMonths,
      reducingBalance: reducing,
      annualRatePercent: annualRate,
    );
    if (problem != null) return problem;

    final cat = catBox.get(categoryId);
    if (cat == null) return 'Choose a category.';
    if (cat.archived) return 'That category is archived. Choose another.';

    final pay = isOpeningBalance ? openingBalanceLabel : paymentMethod.trim();
    if (pay.isEmpty) return 'Choose how it was paid.';

    final v = vendor?.trim();
    var stamp = clock.microsecondsSinceEpoch;
    while (b.containsKey('ast_$stamp')) {
      stamp++;
    }
    final id = 'ast_$stamp';
    await b.put(
      id,
      Asset(
        id: id,
        name: name.trim(),
        categoryId: cat.id,
        purchaseDate: dateOnly(purchaseDate),
        cost: double.parse(cost.toStringAsFixed(2)),
        paymentMethod: pay,
        vendor: (v == null || v.isEmpty) ? null : v,
        usefulLifeMonths: usefulLifeMonths,
        residualValue: double.parse(residualValue.toStringAsFixed(2)),
        method: method,
        annualRate: reducing ? annualRate : null,
        isOpeningBalance: isOpeningBalance,
        notes: notes.trim(),
        createdAt: clock,
      ),
    );
    return null;
  }

  /// Net book value and gain or loss if [a] were retired on [date].
  Disposal? previewRetirement(Asset a, DateTime date, double proceeds) =>
      Depreciation.disposal(specOf(a).withRetirement(
          dateOnly(date), BalanceMath.toMinor(proceeds < 0 ? 0 : proceeds)));

  /// Retires an asset. Returns an error message, or null on success.
  Future<String?> retireAsset(
    Asset a,
    DateTime date, {
    double? proceeds,
    DateTime? now,
  }) async {
    final problem = AssetRules.validateRetire(
      isActive: a.status == Asset.statusActive,
      isVoided: a.voidedAt != null,
      purchaseDate: a.purchaseDate,
      retireDate: date,
      today: now ?? DateTime.now(),
      proceeds: proceeds,
    );
    if (problem != null) return problem;
    a.status = Asset.statusRetired;
    a.retiredDate = dateOnly(date);
    a.disposalProceeds =
        proceeds == null ? null : double.parse(proceeds.toStringAsFixed(2));
    await a.save();
    return null;
  }

  /// Voids an asset. The reason is required. The record stays in storage and
  /// is left out of every total. Returns an error message, or null.
  Future<String?> voidAsset(Asset a, String reason, {DateTime? now}) async {
    final problem =
        AssetRules.validateVoid(reason: reason, isVoided: a.voidedAt != null);
    if (problem != null) return problem;
    a.voidedAt = now ?? DateTime.now();
    a.voidReason = reason.trim();
    await a.save();
    return null;
  }
}
