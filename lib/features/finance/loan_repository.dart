import 'package:hive/hive.dart';

import 'balance_math.dart';
import 'finance_boxes.dart';
import 'finance_repository.dart';
import 'loan_math.dart';
import 'models/loan.dart';
import 'models/loan_transaction.dart';

/// One loan with its computed figures, for the list and detail screens.
class LoanSnapshot {
  final Loan loan;
  final int outstandingMinor;
  final int principalRepaidMinor;
  final int interestPaidMinor;

  const LoanSnapshot({
    required this.loan,
    required this.outstandingMinor,
    required this.principalRepaidMinor,
    required this.interestPaidMinor,
  });

  bool get isVoided => loan.voidedAt != null;
  bool get isSettled => !isVoided && outstandingMinor == 0;
  bool get isActive => !isVoided && outstandingMinor > 0;
}

class LoanTotals {
  final int activeCount;
  final int outstandingMinor;
  const LoanTotals({required this.activeCount, required this.outstandingMinor});
}

/// Reads and writes loans and repayments. Uses only the `hive` package.
/// Rules enforced here (not only in the screens):
///  - no edit and no delete after save; the only change is voiding
///  - a loan with live repayments cannot be voided (void them first)
///  - the principal of a repayment cannot exceed the balance outstanding
///  - an existing loan is entered as its outstanding balance, with no cash inflow
///  - interest is entered by the manager, never calculated
class LoanRepository {
  LoanRepository._();
  static final LoanRepository instance = LoanRepository._();

  /// Stored as "received into" for a loan that already existed.
  static const String openingBalanceLabel = 'Opening balance';

  Box<Loan>? get loanBox {
    try {
      return Hive.isBoxOpen(FinanceBoxes.loansBox)
          ? Hive.box<Loan>(FinanceBoxes.loansBox)
          : null;
    } catch (_) {
      return null;
    }
  }

  Box<LoanTransaction>? get transactionBox {
    try {
      return Hive.isBoxOpen(FinanceBoxes.loanTransactionsBox)
          ? Hive.box<LoanTransaction>(FinanceBoxes.loanTransactionsBox)
          : null;
    } catch (_) {
      return null;
    }
  }

  bool get isReady =>
      loanBox != null &&
      transactionBox != null &&
      FinanceRepository.instance.isReady;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static LoanSpec loanSpec(Loan l) => LoanSpec(
        id: l.id,
        dateReceived: l.dateReceived,
        principalMinor: BalanceMath.toMinor(l.principal),
        voided: l.voidedAt != null,
      );

  static RepaymentSpec repaymentSpec(LoanTransaction t) => RepaymentSpec(
        loanId: t.loanId,
        date: t.date,
        principalMinor: BalanceMath.toMinor(t.principalAmount),
        interestMinor: BalanceMath.toMinor(t.interestAmount),
        voided: t.voidedAt != null,
      );

  List<RepaymentSpec> _allRepaymentSpecs() {
    final b = transactionBox;
    if (b == null) return const [];
    return [for (final t in b.values) repaymentSpec(t)];
  }

  /// Repayments of one loan, newest first. Voided ones are included.
  List<LoanTransaction> repayments(String loanId) {
    final b = transactionBox;
    if (b == null) return const [];
    return [
      for (final t in b.values)
        if (t.loanId == loanId) t,
    ]..sort((a, c) {
        final d = c.date.compareTo(a.date);
        return d != 0 ? d : c.createdAt.compareTo(a.createdAt);
      });
  }

  LoanSnapshot snapshot(Loan l, {List<RepaymentSpec>? specs}) {
    final rs = specs ?? _allRepaymentSpecs();
    final spec = loanSpec(l);
    return LoanSnapshot(
      loan: l,
      outstandingMinor: LoanMath.outstanding(spec, rs),
      principalRepaidMinor: LoanMath.principalRepaid(l.id, rs),
      interestPaidMinor: LoanMath.interestPaid(l.id, rs),
    );
  }

  /// Every loan, newest first. Voided ones are included.
  List<LoanSnapshot> snapshots() {
    final b = loanBox;
    if (b == null) return const [];
    final specs = _allRepaymentSpecs();
    final loans = b.values.toList()
      ..sort((a, c) {
        final d = c.dateReceived.compareTo(a.dateReceived);
        return d != 0 ? d : c.createdAt.compareTo(a.createdAt);
      });
    return [for (final l in loans) snapshot(l, specs: specs)];
  }

  /// Total still owed on loans that are active (not settled, not voided).
  LoanTotals totals() {
    var count = 0;
    var owed = 0;
    for (final s in snapshots()) {
      if (!s.isActive) continue;
      count++;
      owed += s.outstandingMinor;
    }
    return LoanTotals(activeCount: count, outstandingMinor: owed);
  }

  /// Saves a new loan. Returns an error message, or null on success.
  Future<String?> addLoan({
    required String lenderName,
    required String lenderType,
    required DateTime dateReceived,
    required double principal,
    String receivedInto = '',
    double? interestRatePercent,
    int? termMonths,
    String notes = '',
    bool isOpeningBalance = false,
    DateTime? now,
  }) async {
    final b = loanBox;
    if (b == null) return 'Loans are not available on this device.';
    final clock = now ?? DateTime.now();

    final problem = LoanMath.validateNewLoan(
      lenderName: lenderName,
      lenderType: lenderType,
      allowedLenderTypes: Loan.lenderTypes,
      dateReceived: dateReceived,
      today: clock,
      principal: principal,
      isOpeningBalance: isOpeningBalance,
      receivedInto: receivedInto,
      interestRatePercent: interestRatePercent,
      termMonths: termMonths,
    );
    if (problem != null) return problem;

    var stamp = clock.microsecondsSinceEpoch;
    while (b.containsKey('loan_$stamp')) {
      stamp++;
    }
    final id = 'loan_$stamp';
    await b.put(
      id,
      Loan(
        id: id,
        lenderName: lenderName.trim(),
        lenderType: lenderType,
        dateReceived: dateOnly(dateReceived),
        principal: double.parse(principal.toStringAsFixed(2)),
        interestRatePercent: interestRatePercent,
        termMonths: termMonths,
        receivedInto:
            isOpeningBalance ? openingBalanceLabel : receivedInto.trim(),
        notes: notes.trim(),
        isOpeningBalance: isOpeningBalance,
        createdAt: clock,
      ),
    );
    return null;
  }

  /// Saves a repayment split into principal and interest. Returns an error
  /// message, or null on success.
  Future<String?> addRepayment({
    required String loanId,
    required DateTime date,
    double principalAmount = 0,
    double interestAmount = 0,
    required String paymentMethod,
    String note = '',
    DateTime? now,
  }) async {
    final lb = loanBox;
    final tb = transactionBox;
    if (lb == null || tb == null) return 'Loans are not available on this device.';
    final loan = lb.get(loanId);
    if (loan == null) return 'Loan not found.';
    final clock = now ?? DateTime.now();

    if (principalAmount.isNaN ||
        principalAmount.isInfinite ||
        interestAmount.isNaN ||
        interestAmount.isInfinite) {
      return 'Enter valid amounts.';
    }
    final principal = double.parse(principalAmount.toStringAsFixed(2));
    final interest = double.parse(interestAmount.toStringAsFixed(2));

    final outstanding = LoanMath.outstanding(loanSpec(loan), _allRepaymentSpecs());
    final problem = LoanMath.validateRepayment(
      loanVoided: loan.voidedAt != null,
      outstandingMinor: outstanding,
      principalMinor: BalanceMath.toMinor(principal),
      interestMinor: BalanceMath.toMinor(interest),
      date: date,
      loanDate: loan.dateReceived,
      today: clock,
      paymentMethod: paymentMethod,
    );
    if (problem != null) return problem;

    var stamp = clock.microsecondsSinceEpoch;
    while (tb.containsKey('lt_$stamp')) {
      stamp++;
    }
    final id = 'lt_$stamp';
    await tb.put(
      id,
      LoanTransaction(
        id: id,
        loanId: loan.id,
        date: dateOnly(date),
        principalAmount: principal,
        interestAmount: interest,
        paymentMethod: paymentMethod.trim(),
        note: note.trim(),
        createdAt: clock,
      ),
    );
    return null;
  }

  /// Voids a loan. Refused while it still has repayments that are not voided.
  Future<String?> voidLoan(Loan loan, String reason, {DateTime? now}) async {
    final live = repayments(loan.id).any((t) => t.voidedAt == null);
    final problem = LoanMath.validateVoidLoan(
      reason: reason,
      isVoided: loan.voidedAt != null,
      hasActiveRepayments: live,
    );
    if (problem != null) return problem;
    loan.voidedAt = now ?? DateTime.now();
    loan.voidReason = reason.trim();
    await loan.save();
    return null;
  }

  /// Voids a repayment. The record stays; the balance goes back up.
  Future<String?> voidRepayment(LoanTransaction t, String reason,
      {DateTime? now}) async {
    final problem = LoanMath.validateVoidRepayment(
        reason: reason, isVoided: t.voidedAt != null);
    if (problem != null) return problem;
    t.voidedAt = now ?? DateTime.now();
    t.voidReason = reason.trim();
    await t.save();
    return null;
  }
}
