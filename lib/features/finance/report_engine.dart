import 'depreciation.dart';
import 'legacy_balance_resolver.dart';
import 'loan_math.dart';
import 'report_data.dart';
import 'report_inputs.dart';
import 'report_period.dart';

/// The report engine (handoff section 6). Pure Dart: no Hive, no Flutter.
///
/// Given the shop's records and a period it works out every figure of the
/// financial report once, so the screen and the Excel file always agree.
///
/// Rules it follows:
///  - A sale is counted once, on the day of the original receipt, at its full
///    value. Balance payments are cash received, never new sales.
///  - Old typed balance receipts that were linked to their sale are not new
///    sales either. A pure balance receipt adds no sales. A receipt that also
///    sold new items adds total minus the amount applied to the old balance.
///    Old receipts not yet linked stay in sales and are flagged.
///  - Written-off balances ("Settle with adjustment") reduce revenue and the
///    amount owed, and move no cash.
///  - Voided entries are never counted.
///  - Not-in-P&L money (drawings, tax) stays out of the P&L but is in Cashflow.
///  - Depreciation, loan balances and net book value come from the asset and
///    loan registers. Nothing is typed in.
class ReportEngine {
  ReportEngine._();

  /// The seeded "Owner drawings" category. Any other Not-in-P&L category is
  /// treated as a tax or similar remittance in Cashflow.
  static const String drawingsCategoryId = 'seed_np_drawings';

  /// Cash by method when the method is not known (for example sale proceeds).
  static const String notRecorded = 'Not recorded';

  /// Fixed wording for how figures are recognised (handoff 6.4).
  static const List<String> basis = [
    'Sales revenue is counted once, on the original receipt date, at the full '
        'receipt value, whatever the deposit.',
    'Balance payments never add to sales. They only affect Cashflow and '
        'Receivables.',
    'Direct costs and operating expenses are counted when incurred (the '
        'expense date).',
    'Cashflow is cash-basis: it follows when money actually moved.',
    'Asset purchases are capitalised. They never hit the P&L at purchase; '
        'their cost reaches the P&L gradually as depreciation, which is '
        'non-cash and left out of Cashflow.',
    'Loan receipts are not income and principal repayments are not expenses. '
        'Only the interest part of a repayment is a cost, counted on the day '
        'it is paid, with no accrual of unpaid interest.',
    'Interest paid is a finance cost below operating profit in the P&L and '
        'its own line under Financing in Cashflow.',
    'Not in P&L expenses (owner drawings, tax remittances) never reach the '
        'P&L. They appear only in Cashflow.',
    'Settlement adjustments (written-off balances) reduce revenue and '
        'Receivables but move no cash.',
  ];

  static ReportData generate(
    ReportInput input,
    ReportPeriod period, {
    DateTime? generatedAt,
    String appVersion = '',
  }) =>
      _Builder(input, period, generatedAt, appVersion).build();
}

class _Pay {
  final DateTime date;
  final int amountMinor;
  const _Pay(this.date, this.amountMinor);
}

class _Cash {
  int salesDeposits = 0;
  int balancePayments = 0;
  int expensesPaid = 0;
  int taxesRemitted = 0;
  int assetPurchases = 0;
  int disposalProceeds = 0;
  int loansReceived = 0;
  int principalRepaid = 0;
  int interestPaid = 0;
  int ownerDrawings = 0;
  final Map<String, int> inByMethod = {};
  final Map<String, int> outByMethod = {};

  int get operatingIn => salesDeposits + balancePayments;
  int get operatingOut => expensesPaid + taxesRemitted;
  int get netOperating => operatingIn - operatingOut;
  int get netInvesting => disposalProceeds - assetPurchases;
  int get netFinancing =>
      loansReceived - principalRepaid - interestPaid - ownerDrawings;
  int get net => netOperating + netInvesting + netFinancing;

  static String _key(String m) =>
      m.trim().isEmpty ? ReportEngine.notRecorded : m.trim();

  void addIn(String method, int v) {
    if (v == 0) return;
    final k = _key(method);
    inByMethod[k] = (inByMethod[k] ?? 0) + v;
  }

  void addOut(String method, int v) {
    if (v == 0) return;
    final k = _key(method);
    outByMethod[k] = (outByMethod[k] ?? 0) + v;
  }
}

class _Builder {
  final ReportInput input;
  final ReportPeriod period;
  final DateTime? generatedAt;
  final String appVersion;

  late final Map<String, LegacyBalanceEntry> legacy = {
    for (final e in input.legacy.entries) e.code: e,
  };

  /// Payments that reduce what a sale owes, by sale code: balance receipts,
  /// linked old balance receipts, and write-offs.
  late final Map<String, List<_Pay>> payments = _indexPayments();

  _Builder(this.input, this.period, this.generatedAt, this.appVersion);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _in(DateTime d, DateTime from, DateTime to) {
    final x = _day(d);
    return !x.isBefore(from) && !x.isAfter(to);
  }

  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;

  Map<String, List<_Pay>> _indexPayments() {
    final map = <String, List<_Pay>>{};
    void add(String code, DateTime date, int amount) =>
        map.putIfAbsent(code, () => []).add(_Pay(_day(date), amount));

    for (final r in input.receipts) {
      if (r.isBalancePayment && r.linkedCode != null) {
        add(r.linkedCode!, r.issuedAt, r.totalMinor);
      }
    }
    for (final e in input.legacy.entries) {
      if (e.isLinked && e.originalCode != null && e.appliedMinor > 0) {
        add(e.originalCode!, e.issuedAt, e.appliedMinor);
      }
    }
    for (final w in input.writeoffs) {
      add(w.receiptCode, w.date, w.amountMinor);
    }
    return map;
  }

  // ---- what a sale still owes on a given day --------------------------------

  /// Never below zero. A linked old balance receipt owes nothing of its own;
  /// a receipt that also sold new items keeps its own unpaid part.
  int _outstandingAt(ReportReceipt r, DateTime asOf) {
    final e = legacy[r.code];
    if (e != null && e.isLinked && !e.isMixed) return 0;
    var left = r.totalMinor - r.depositMinor;
    for (final p in payments[r.code] ?? const <_Pay>[]) {
      if (!p.date.isAfter(asOf)) left -= p.amountMinor;
    }
    return left < 0 ? 0 : left;
  }

  /// What a receipt adds to sales.
  int _revenueOf(ReportReceipt r) {
    final e = legacy[r.code];
    if (e != null && e.isLinked) {
      if (!e.isMixed) return 0;
      final v = r.totalMinor - e.appliedMinor;
      return v < 0 ? 0 : v;
    }
    return r.totalMinor;
  }

  /// True for a pure old balance receipt that was linked: not a sale at all.
  bool _isLinkedPureBalance(ReportReceipt r) {
    final e = legacy[r.code];
    return e != null && e.isLinked && !e.isMixed;
  }

  // ---- cash between two dates ------------------------------------------------

  _Cash _cashBetween(DateTime from, DateTime to) {
    final c = _Cash();

    for (final r in input.receipts) {
      if (!_in(r.issuedAt, from, to)) continue;
      if (r.isBalancePayment) {
        c.balancePayments += r.totalMinor;
        c.addIn(r.paymentMethod, r.totalMinor);
        continue;
      }
      final e = legacy[r.code];
      var share = 0;
      if (e != null && e.isLinked) {
        share = e.appliedMinor < r.depositMinor ? e.appliedMinor : r.depositMinor;
        if (share < 0) share = 0;
      }
      c.balancePayments += share;
      c.salesDeposits += r.depositMinor - share;
      c.addIn(r.paymentMethod, r.depositMinor);
    }

    for (final x in input.expenses) {
      if (x.voided || !_in(x.date, from, to)) continue;
      if (x.group == 'direct' || x.group == 'operating') {
        c.expensesPaid += x.amountMinor;
      } else if (x.categoryId == ReportEngine.drawingsCategoryId) {
        c.ownerDrawings += x.amountMinor;
      } else {
        c.taxesRemitted += x.amountMinor;
      }
      c.addOut(x.paidFrom, x.amountMinor);
    }

    for (final a in input.assets) {
      if (a.spec.voided) continue;
      if (!a.isOpeningBalance && _in(a.spec.purchaseDate, from, to)) {
        c.assetPurchases += a.spec.costMinor;
        c.addOut(a.paymentMethod, a.spec.costMinor);
      }
      final retired = a.spec.retiredDate;
      if (retired != null &&
          a.spec.proceedsMinor > 0 &&
          _in(retired, from, to)) {
        c.disposalProceeds += a.spec.proceedsMinor;
        c.addIn(ReportEngine.notRecorded, a.spec.proceedsMinor);
      }
    }

    final voidedLoans = {
      for (final l in input.loans)
        if (l.spec.voided) l.id,
    };
    for (final l in input.loans) {
      if (l.spec.voided || l.isOpeningBalance) continue;
      if (_in(l.spec.dateReceived, from, to)) {
        c.loansReceived += l.spec.principalMinor;
        c.addIn(l.receivedInto, l.spec.principalMinor);
      }
    }
    for (final p in input.repayments) {
      final r = p.spec;
      if (r.voided || voidedLoans.contains(r.loanId)) continue;
      if (!_in(r.date, from, to)) continue;
      c.principalRepaid += r.principalMinor;
      c.interestPaid += r.interestMinor;
      c.addOut(p.paymentMethod, r.principalMinor + r.interestMinor);
    }
    return c;
  }

  // ---- build -----------------------------------------------------------------

  ReportData build() {
    final from = period.from;
    final to = period.to;

    final saleReceipts = [
      for (final r in input.receipts)
        if (!r.isBalancePayment) r,
    ];

    // Receivables on the last day of the period.
    final receivableRows = <ReceivableRow>[];
    final outstandingAtEnd = <String, int>{};
    for (final r in saleReceipts) {
      if (_day(r.issuedAt).isAfter(to)) continue;
      final out = _outstandingAt(r, to);
      outstandingAtEnd[r.code] = out;
      if (out > 0) {
        receivableRows.add(ReceivableRow(
          code: r.code,
          customerName: r.customerName,
          issuedAt: r.issuedAt,
          totalMinor: r.totalMinor,
          settledMinor: r.totalMinor - out,
          outstandingMinor: out,
          ageDays: _daysBetween(_day(r.issuedAt), to),
        ));
      }
    }
    receivableRows.sort((a, b) {
      final d = a.issuedAt.compareTo(b.issuedAt);
      return d != 0 ? d : a.code.compareTo(b.code);
    });
    final receivables = ReceivablesSection(
      rows: receivableRows,
      totalMinor: receivableRows.fold(0, (s, r) => s + r.outstandingMinor),
    );

    // Sales.
    final salesRows = <SalesRow>[];
    for (final r in saleReceipts) {
      if (!_in(r.issuedAt, from, to)) continue;
      if (_isLinkedPureBalance(r)) continue;
      final e = legacy[r.code];
      String status;
      if (e != null && e.isLinked) {
        status = 'Includes old balance payment';
      } else if (e != null) {
        status = 'Possible balance payment (unmatched)';
      } else {
        final out = outstandingAtEnd[r.code] ?? 0;
        status = out > 0
            ? 'Owing'
            : (r.balanceAtTimeMinor > 0 ? 'Settled later' : 'Paid');
      }
      salesRows.add(SalesRow(
        date: _day(r.issuedAt),
        code: r.code,
        customerName: r.customerName,
        itemsSummary: r.itemsSummary,
        totalMinor: r.totalMinor,
        discountMinor: r.discountMinor,
        depositMinor: r.depositMinor,
        balanceAtTimeMinor: r.balanceAtTimeMinor,
        revenueMinor: _revenueOf(r),
        status: status,
      ));
    }
    salesRows.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.code.compareTo(b.code);
    });
    final sales = _buildSales(salesRows);

    // Expenses.
    final expenses = _buildExpenses();

    // Stock adjustment.
    final counts = [...input.stockCounts]..sort((a, b) => a.date.compareTo(b.date));
    ReportStockCount? openingCount;
    ReportStockCount? closingCount;
    for (final c in counts) {
      final d = _day(c.date);
      if (!d.isAfter(period.dayBefore)) openingCount = c;
      if (!d.isAfter(to)) closingCount = c;
    }
    final stockAdjusted = openingCount != null && closingCount != null;
    final purchases = expenses.directMinor;
    final directCosts = stockAdjusted
        ? openingCount.valueMinor + purchases - closingCount.valueMinor
        : purchases;

    // Settlement adjustments taken in the period.
    var adjustments = 0;
    for (final w in input.writeoffs) {
      if (_in(w.date, from, to)) adjustments += w.amountMinor;
    }

    // Assets.
    final assetSpecs = [for (final a in input.assets) a.spec];
    final depreciation = Depreciation.totalCharge(assetSpecs, from, to);
    var disposalGainLoss = 0;
    for (final a in input.assets) {
      if (a.spec.voided) continue;
      if (!Depreciation.retiredWithin(a.spec, from, to)) continue;
      disposalGainLoss += Depreciation.disposal(a.spec)!.gainLossMinor;
    }
    var assetNbv = 0;
    for (final a in input.assets) {
      final s = a.spec;
      if (s.voided || _day(s.purchaseDate).isAfter(to)) continue;
      final retired = s.retiredDate;
      if (retired != null && !_day(retired).isAfter(to)) continue;
      assetNbv += Depreciation.netBookValue(s, to);
    }

    // Loans.
    final liveRepayments = [
      for (final p in input.repayments)
        if (!_loanIsVoided(p.spec.loanId)) p.spec,
    ];
    final loanTotals = LoanMath.repaymentsBetween(liveRepayments, from, to);
    var loansOutstanding = 0;
    for (final l in input.loans) {
      if (l.spec.voided) continue;
      // A loan that already existed counts from the start of time.
      final spec = l.isOpeningBalance
          ? LoanSpec(
              id: l.spec.id,
              dateReceived: DateTime(1900),
              principalMinor: l.spec.principalMinor,
            )
          : l.spec;
      loansOutstanding += LoanMath.outstanding(spec, liveRepayments, asOf: to);
    }

    // Profit and loss.
    final grossProfit = sales.revenueMinor - adjustments - directCosts;
    final opBeforeDep = grossProfit - expenses.operatingMinor;
    final operatingProfit = opBeforeDep - depreciation + disposalGainLoss;
    final npbt = operatingProfit - loanTotals.interestMinor;
    final rate = input.settings.estimatedTaxRatePercent;
    final tax = (rate > 0 && npbt > 0) ? ((npbt * rate) / 100).round() : 0;
    final pnl = PnlSection(
      revenueMinor: sales.revenueMinor,
      settlementAdjustmentsMinor: adjustments,
      purchasesMinor: purchases,
      openingStockMinor: stockAdjusted ? openingCount.valueMinor : null,
      closingStockMinor: stockAdjusted ? closingCount.valueMinor : null,
      stockAdjusted: stockAdjusted,
      directCostsMinor: directCosts,
      grossProfitMinor: grossProfit,
      operatingExpensesMinor: expenses.operatingMinor,
      operatingProfitBeforeDepreciationMinor: opBeforeDep,
      depreciationMinor: depreciation,
      disposalGainLossMinor: disposalGainLoss,
      operatingProfitMinor: operatingProfit,
      interestPaidMinor: loanTotals.interestMinor,
      netProfitBeforeTaxMinor: npbt,
      estimatedTaxMinor: tax,
      netProfitAfterTaxMinor: npbt - tax,
    );

    // Cashflow.
    final cash = _cashBetween(from, to);
    final s = input.settings;
    var opening = s.openingCashMinor;
    var afterStart = false;
    final base = s.openingCashDate == null ? DateTime(1900) : _day(s.openingCashDate!);
    if (s.openingCashDate != null && base.isAfter(from)) {
      afterStart = true;
    } else if (!base.isAfter(period.dayBefore)) {
      opening += _cashBetween(base, period.dayBefore).net;
    }
    final methods = {...cash.inByMethod.keys, ...cash.outByMethod.keys}.toList()
      ..sort();
    final cashflow = CashflowSection(
      openingBalanceMinor: opening,
      salesDepositsMinor: cash.salesDeposits,
      balancePaymentsMinor: cash.balancePayments,
      operatingInMinor: cash.operatingIn,
      expensesPaidMinor: cash.expensesPaid,
      taxesRemittedMinor: cash.taxesRemitted,
      operatingOutMinor: cash.operatingOut,
      netOperatingMinor: cash.netOperating,
      assetPurchasesMinor: cash.assetPurchases,
      disposalProceedsMinor: cash.disposalProceeds,
      netInvestingMinor: cash.netInvesting,
      loansReceivedMinor: cash.loansReceived,
      principalRepaidMinor: cash.principalRepaid,
      interestPaidMinor: cash.interestPaid,
      ownerDrawingsMinor: cash.ownerDrawings,
      netFinancingMinor: cash.netFinancing,
      netChangeMinor: cash.net,
      closingBalanceMinor: opening + cash.net,
      byMethod: [
        for (final m in methods)
          MethodCash(
            method: m,
            inMinor: cash.inByMethod[m] ?? 0,
            outMinor: cash.outByMethod[m] ?? 0,
          ),
      ],
      openingCashAfterPeriodStart: afterStart,
    );

    // Summary.
    final top = [...expenses.byCategory]
      ..sort((a, b) {
        final d = b.amountMinor.compareTo(a.amountMinor);
        return d != 0 ? d : a.name.compareTo(b.name);
      });
    final summary = SummarySection(
      totalSalesMinor: sales.revenueMinor,
      balancePaymentsCollectedMinor: cashflow.balancePaymentsMinor,
      totalExpensesMinor: expenses.totalMinor,
      depreciationMinor: depreciation,
      interestPaidMinor: loanTotals.interestMinor,
      grossProfitMinor: grossProfit,
      netProfitMinor: npbt,
      estimatedTaxMinor: tax,
      netProfitAfterTaxMinor: npbt - tax,
      cashInMinor: cashflow.cashInMinor,
      cashOutMinor: cashflow.cashOutMinor,
      cashNetMinor: cashflow.netChangeMinor,
      receivablesMinor: receivables.totalMinor,
      assetNetBookValueMinor: assetNbv,
      loansOutstandingMinor: loansOutstanding,
      topCategories: top.take(5).toList(),
      unmatchedCount: input.legacy.needsReviewCount,
    );

    final fixedAssets = _buildFixedAssets();
    final loans = _buildLoans(liveRepayments);
    final filing = _buildFiling(pnl, expenses, receivables, counts, assetNbv,
        loansOutstanding);
    final unmatched = _buildUnmatched();
    final notes = _buildNotes(pnl, cashflow, expenses, unmatched, adjustments);

    return ReportData(
      from: from,
      to: to,
      periodLabel: period.label,
      summary: summary,
      sales: sales,
      expenses: expenses,
      pnl: pnl,
      cashflow: cashflow,
      receivables: receivables,
      fixedAssets: fixedAssets,
      loans: loans,
      filing: filing,
      unmatched: unmatched,
      notes: notes,
    );
  }

  bool _loanIsVoided(String loanId) {
    for (final l in input.loans) {
      if (l.id == loanId) return l.spec.voided;
    }
    return false;
  }

  // ---- fixed assets ------------------------------------------------------------

  FixedAssetsSection _buildFixedAssets() {
    final from = period.from;
    final to = period.to;
    // Depreciation is charged in whole months, so the "start" balance is the
    // end of the month before the period's first month. That keeps start +
    // charge = end for every asset.
    final startBoundary = DateTime(from.year, from.month, 0);

    final assets = [...input.assets]..sort((a, b) {
        final d = a.spec.purchaseDate.compareTo(b.spec.purchaseDate);
        return d != 0 ? d : a.id.compareTo(b.id);
      });

    final rows = <FixedAssetRow>[];
    final additions = <AssetAddition>[];
    final disposals = <AssetDisposal>[];

    for (final a in assets) {
      final s = a.spec;
      if (s.voided || _day(s.purchaseDate).isAfter(to)) continue;
      final retired = s.retiredDate;
      final retiredBefore = retired != null &&
          Depreciation.monthIndex(retired) < Depreciation.monthIndex(from);
      if (retiredBefore) continue;

      final accStart = Depreciation.accumulated(s, startBoundary);
      final accEnd = Depreciation.accumulated(s, to);
      final disposedByEnd = retired != null && !_day(retired).isAfter(to);
      final retiredIn = Depreciation.retiredWithin(s, from, to);

      rows.add(FixedAssetRow(
        name: a.name,
        categoryName: a.categoryName,
        purchaseDate: _day(s.purchaseDate),
        costMinor: s.costMinor,
        method: s.reducingBalance ? 'Reducing balance' : 'Straight-line',
        isOpeningBalance: a.isOpeningBalance,
        accumulatedAtStartMinor: accStart,
        chargeMinor: accEnd - accStart,
        accumulatedAtEndMinor: accEnd,
        netBookValueMinor: s.costMinor - accEnd,
        carryingMinor: disposedByEnd ? 0 : s.costMinor - accEnd,
        retiredDate: retired == null ? null : _day(retired),
        retiredInPeriod: retiredIn,
      ));

      if (_in(s.purchaseDate, from, to)) {
        additions.add(AssetAddition(
          name: a.name,
          purchaseDate: _day(s.purchaseDate),
          costMinor: s.costMinor,
          isOpeningBalance: a.isOpeningBalance,
          paymentMethod: a.paymentMethod,
        ));
      }
      if (retiredIn) {
        final d = Depreciation.disposal(s)!;
        disposals.add(AssetDisposal(
          name: a.name,
          date: _day(retired!),
          proceedsMinor: d.proceedsMinor,
          nbvAtDisposalMinor: d.nbvMinor,
          gainLossMinor: d.gainLossMinor,
        ));
      }
    }

    disposals.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.name.compareTo(b.name);
    });

    int sumRows(int Function(FixedAssetRow r) f) =>
        rows.fold(0, (t, r) => t + f(r));
    return FixedAssetsSection(
      rows: rows,
      additions: additions,
      disposals: disposals,
      costMinor: sumRows((r) => r.costMinor),
      accumulatedAtStartMinor: sumRows((r) => r.accumulatedAtStartMinor),
      chargeMinor: sumRows((r) => r.chargeMinor),
      accumulatedAtEndMinor: sumRows((r) => r.accumulatedAtEndMinor),
      netBookValueMinor: sumRows((r) => r.netBookValueMinor),
      carryingMinor: sumRows((r) => r.carryingMinor),
      additionsCostMinor: additions.fold(0, (t, x) => t + x.costMinor),
      additionsCashMinor: additions
          .where((x) => !x.isOpeningBalance)
          .fold(0, (t, x) => t + x.costMinor),
      disposalProceedsMinor: disposals.fold(0, (t, x) => t + x.proceedsMinor),
      disposalNbvMinor: disposals.fold(0, (t, x) => t + x.nbvAtDisposalMinor),
      disposalGainLossMinor: disposals.fold(0, (t, x) => t + x.gainLossMinor),
    );
  }

  // ---- loans -------------------------------------------------------------------

  LoansSection _buildLoans(List<RepaymentSpec> live) {
    final from = period.from;
    final to = period.to;
    final lenderById = {for (final l in input.loans) l.id: l.lenderName};

    final rows = <LoanRowData>[];
    for (final l in input.loans) {
      if (l.spec.voided) continue;
      // A loan that already existed counts from the start of time.
      final spec = l.isOpeningBalance
          ? LoanSpec(
              id: l.spec.id,
              dateReceived: DateTime(1900),
              principalMinor: l.spec.principalMinor,
            )
          : l.spec;
      final start = LoanMath.outstanding(spec, live, asOf: period.dayBefore);
      final end = LoanMath.outstanding(spec, live, asOf: to);
      final received = (!l.isOpeningBalance && _in(l.spec.dateReceived, from, to))
          ? l.spec.principalMinor
          : 0;
      final paid = LoanMath.repaymentsBetween(
          [for (final r in live) if (r.loanId == l.id) r], from, to);
      if (start == 0 &&
          received == 0 &&
          end == 0 &&
          paid.principalMinor == 0 &&
          paid.interestMinor == 0) {
        continue;
      }
      rows.add(LoanRowData(
        lenderName: l.lenderName,
        lenderType: l.lenderType,
        isOpeningBalance: l.isOpeningBalance,
        balanceAtStartMinor: start,
        receivedMinor: received,
        principalRepaidMinor: paid.principalMinor,
        balanceAtEndMinor: end,
        interestPaidMinor: paid.interestMinor,
        settled: end == 0 && (start > 0 || received > 0),
      ));
    }
    rows.sort((a, b) => a.lenderName.compareTo(b.lenderName));

    final repayments = <LoanRepaymentRow>[];
    for (final p in input.repayments) {
      final r = p.spec;
      if (r.voided || !_in(r.date, from, to)) continue;
      if (!lenderById.containsKey(r.loanId) || _loanIsVoided(r.loanId)) continue;
      repayments.add(LoanRepaymentRow(
        date: _day(r.date),
        lenderName: lenderById[r.loanId]!,
        principalMinor: r.principalMinor,
        interestMinor: r.interestMinor,
        paymentMethod: p.paymentMethod,
        note: p.note,
      ));
    }
    repayments.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.lenderName.compareTo(b.lenderName);
    });

    int sum(int Function(LoanRowData r) f) => rows.fold(0, (t, r) => t + f(r));
    return LoansSection(
      rows: rows,
      repayments: repayments,
      balanceAtStartMinor: sum((r) => r.balanceAtStartMinor),
      receivedMinor: sum((r) => r.receivedMinor),
      principalRepaidMinor: sum((r) => r.principalRepaidMinor),
      balanceAtEndMinor: sum((r) => r.balanceAtEndMinor),
      interestPaidMinor: sum((r) => r.interestPaidMinor),
    );
  }

  // ---- filing figures ----------------------------------------------------------

  FilingSection _buildFiling(
    PnlSection pnl,
    ExpensesSection expenses,
    ReceivablesSection receivables,
    List<ReportStockCount> counts,
    int assetNbv,
    int loansOutstanding,
  ) {
    final s = input.settings;

    // VAT noted on expenses in the period, not voided.
    var inputVat = 0;
    for (final x in input.expenses) {
      if (x.voided || !_in(x.date, period.from, period.to)) continue;
      inputVat += x.inputVatMinor ?? 0;
    }

    int? vatCollected;
    int? vatPayable;
    if (s.vatEnabled) {
      // Receipt totals are taken to include VAT.
      final rate = s.vatRatePercent;
      vatCollected = rate > 0
          ? ((pnl.revenueMinor * rate) / (100 + rate)).round()
          : 0;
      vatPayable = vatCollected - inputVat;
    }

    int? closingStock;
    for (final c in counts) {
      if (!_day(c.date).isAfter(period.to)) closingStock = c.valueMinor;
    }

    return FilingSection(
      turnoverMinor: pnl.revenueMinor,
      directCostsMinor: pnl.directCostsMinor,
      operatingExpensesMinor: pnl.operatingExpensesMinor,
      bookDepreciationMinor: pnl.depreciationMinor,
      interestPaidMinor: pnl.interestPaidMinor,
      disposalGainLossMinor: pnl.disposalGainLossMinor,
      netProfitBeforeTaxMinor: pnl.netProfitBeforeTaxMinor,
      vatEnabled: s.vatEnabled,
      vatRatePercent: s.vatRatePercent,
      vatCollectedMinor: vatCollected,
      inputVatPaidMinor: inputVat,
      vatPayableMinor: vatPayable,
      estimatedTaxMinor:
          s.estimatedTaxRatePercent > 0 ? pnl.estimatedTaxMinor : null,
      receivablesMinor: receivables.totalMinor,
      closingStockMinor: closingStock,
      assetNetBookValueMinor: assetNbv,
      loansOutstandingMinor: loansOutstanding,
    );
  }

  // ---- unmatched balance payments --------------------------------------------

  UnmatchedSection _buildUnmatched() {
    final rows = <UnmatchedRow>[];
    for (final e in input.legacy.entries) {
      if (e.isLinked) continue;
      rows.add(UnmatchedRow(
        code: e.code,
        date: _day(e.issuedAt),
        customerName: e.customerName,
        paidMinor: e.paidMinor,
        reason: e.reason?.label ?? '',
        textSnippet: e.textSnippet,
        referencesFound: e.referencesFound.join(', '),
        suggestions: [for (final x in e.suggestions.take(3)) x.code],
        inPeriod: _in(e.issuedAt, period.from, period.to),
      ));
    }
    rows.sort((a, b) {
      final d = a.date.compareTo(b.date);
      return d != 0 ? d : a.code.compareTo(b.code);
    });
    return UnmatchedSection(rows: rows);
  }

  // ---- notes -------------------------------------------------------------------

  static String _money(int minor) {
    final neg = minor < 0;
    final v = neg ? -minor : minor;
    final whole = (v ~/ 100).toString();
    final cents = (v % 100).toString().padLeft(2, '0');
    final buf = StringBuffer();
    for (var i = 0; i < whole.length; i++) {
      if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
      buf.write(whole[i]);
    }
    return '${neg ? '-' : ''}$buf.$cents';
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  NotesSection _buildNotes(
    PnlSection pnl,
    CashflowSection cashflow,
    ExpensesSection expenses,
    UnmatchedSection unmatched,
    int adjustments,
  ) {
    final s = input.settings;
    final notes = <String>[
      'Period: ${_date(period.from)} to ${_date(period.to)}.',
    ];

    if (pnl.stockAdjusted) {
      notes.add('Direct costs include a stock adjustment: opening stock '
          '${_money(pnl.openingStockMinor!)} + purchases '
          '${_money(pnl.purchasesMinor)} - closing stock '
          '${_money(pnl.closingStockMinor!)}.');
    } else {
      notes.add('No stock adjustment: direct costs equal purchases in the '
          'period. It needs a stock count on or before the day before the '
          'period starts and another on or before its end.');
    }

    final lastDay = DateTime(period.to.year, period.to.month + 1, 0).day;
    if (period.from.day != 1 || period.to.day != lastDay) {
      notes.add('This period does not start and end on month boundaries. '
          'Depreciation is charged in whole months, so figures for periods '
          'that overlap will not add up.');
    }

    if (cashflow.openingCashAfterPeriodStart) {
      notes.add('The opening cash date is after this period starts, so the '
          'opening balance is shown as entered and earlier cash movements '
          'are not included.');
    }

    if (unmatched.count > 0) {
      notes.add('${unmatched.count} old balance receipt(s) are not linked to '
          'their sale yet. Until they are linked they are counted as sales. '
          'See the Unmatched Balance Payments sheet.');
    }

    if (adjustments > 0) {
      notes.add('Settlement adjustments of ${_money(adjustments)} (written-off '
          'balances) were deducted from revenue and from receivables. No cash '
          'moved.');
    }

    if (s.vatEnabled) {
      notes.add('VAT collected is worked out from sales as if receipt totals '
          'include VAT at ${s.vatRatePercent}%. Input VAT is the figure '
          'noted on expenses and is information only.');
    }

    if (s.estimatedTaxRatePercent > 0) {
      notes.add('Estimated tax is an estimate only: '
          '${s.estimatedTaxRatePercent}% of net profit before tax, and only '
          'when that profit is above zero.');
    }

    notes.add('Not in P&L categories other than Owner drawings are treated as '
        'tax or similar remittances in Cashflow (operating). Owner drawings '
        'are shown under Financing.');
    notes.add('Equipment and loans entered as opening balances create no cash '
        'movement.');
    if (expenses.voidedRows.isNotEmpty) {
      notes.add('${expenses.voidedRows.length} voided expense(s) are listed on '
          'the Expenses sheet and are not counted anywhere.');
    }

    return NotesSection(
      generatedAt: generatedAt,
      appVersion: appVersion,
      basis: ReportEngine.basis,
      notes: notes,
    );
  }

  // ---- sales -----------------------------------------------------------------

  SalesSection _buildSales(List<SalesRow> rows) {
    SalesBucket bucket(DateTime key, List<SalesRow> rs) => SalesBucket(
          key: key,
          count: rs.length,
          revenueMinor: rs.fold(0, (s, r) => s + r.revenueMinor),
          discountMinor: rs.fold(0, (s, r) => s + r.discountMinor),
          depositMinor: rs.fold(0, (s, r) => s + r.depositMinor),
        );

    final days = <DateTime, List<SalesRow>>{};
    final months = <DateTime, List<SalesRow>>{};
    for (final r in rows) {
      days.putIfAbsent(r.date, () => []).add(r);
      months.putIfAbsent(DateTime(r.date.year, r.date.month), () => []).add(r);
    }
    final dayKeys = days.keys.toList()..sort();
    final monthKeys = months.keys.toList()..sort();
    return SalesSection(
      rows: rows,
      byDay: [for (final k in dayKeys) bucket(k, days[k]!)],
      byMonth: [for (final k in monthKeys) bucket(k, months[k]!)],
      count: rows.length,
      revenueMinor: rows.fold(0, (s, r) => s + r.revenueMinor),
      discountMinor: rows.fold(0, (s, r) => s + r.discountMinor),
      depositMinor: rows.fold(0, (s, r) => s + r.depositMinor),
    );
  }

  // ---- expenses --------------------------------------------------------------

  ExpensesSection _buildExpenses() {
    final inPeriod = [
      for (final x in input.expenses)
        if (_in(x.date, period.from, period.to)) x,
    ]..sort((a, b) {
        final d = a.date.compareTo(b.date);
        return d != 0 ? d : a.id.compareTo(b.id);
      });

    ExpenseRowData row(ReportExpense x) => ExpenseRowData(
          date: _day(x.date),
          categoryName: x.categoryName,
          group: x.group,
          amountMinor: x.amountMinor,
          paidFrom: x.paidFrom,
          vendor: x.vendor,
          inputVatMinor: x.inputVatMinor,
          whtMinor: x.whtMinor,
          description: x.description,
          enteredBy: x.enteredBy,
          voided: x.voided,
          voidReason: x.voidReason,
        );

    final rows = <ExpenseRowData>[];
    final notInPnl = <ExpenseRowData>[];
    final voided = <ExpenseRowData>[];
    final catTotals = <String, _CatAcc>{};
    final npTotals = <String, _CatAcc>{};
    final monthDirect = <DateTime, int>{};
    final monthOperating = <DateTime, int>{};
    var direct = 0;
    var operating = 0;
    var notInPnlSum = 0;

    for (final x in inPeriod) {
      if (x.voided) {
        voided.add(row(x));
        continue;
      }
      final isPnl = x.group == 'direct' || x.group == 'operating';
      if (isPnl) {
        rows.add(row(x));
        catTotals
            .putIfAbsent(x.categoryId, () => _CatAcc(x.categoryName, x.group))
            .add(x.amountMinor);
        final m = DateTime(x.date.year, x.date.month);
        if (x.group == 'direct') {
          direct += x.amountMinor;
          monthDirect[m] = (monthDirect[m] ?? 0) + x.amountMinor;
          monthOperating.putIfAbsent(m, () => 0);
        } else {
          operating += x.amountMinor;
          monthOperating[m] = (monthOperating[m] ?? 0) + x.amountMinor;
          monthDirect.putIfAbsent(m, () => 0);
        }
      } else {
        notInPnl.add(row(x));
        notInPnlSum += x.amountMinor;
        npTotals
            .putIfAbsent(x.categoryId, () => _CatAcc(x.categoryName, x.group))
            .add(x.amountMinor);
      }
    }

    List<CategoryTotal> totalsList(Map<String, _CatAcc> m) {
      final list = [
        for (final e in m.entries)
          CategoryTotal(
            categoryId: e.key,
            name: e.value.name,
            group: e.value.group,
            amountMinor: e.value.amount,
            count: e.value.count,
          ),
      ];
      int groupOrder(String g) => g == 'direct' ? 0 : (g == 'operating' ? 1 : 2);
      list.sort((a, b) {
        final g = groupOrder(a.group).compareTo(groupOrder(b.group));
        if (g != 0) return g;
        final d = b.amountMinor.compareTo(a.amountMinor);
        return d != 0 ? d : a.name.compareTo(b.name);
      });
      return list;
    }

    final monthKeys = monthDirect.keys.toList()..sort();
    return ExpensesSection(
      rows: rows,
      notInPnlRows: notInPnl,
      voidedRows: voided,
      byCategory: totalsList(catTotals),
      notInPnlByCategory: totalsList(npTotals),
      byMonth: [
        for (final k in monthKeys)
          ExpenseMonth(
            month: k,
            directMinor: monthDirect[k] ?? 0,
            operatingMinor: monthOperating[k] ?? 0,
          ),
      ],
      directMinor: direct,
      operatingMinor: operating,
      notInPnlMinor: notInPnlSum,
    );
  }
}

class _CatAcc {
  final String name;
  final String group;
  int amount = 0;
  int count = 0;
  _CatAcc(this.name, this.group);
  void add(int v) {
    amount += v;
    count++;
  }
}
