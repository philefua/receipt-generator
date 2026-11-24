/// Pure loan maths and checks (handoff 6B). No Hive, no Flutter.
///
/// A loan is money received that must be paid back: cash in (financing) and a
/// liability, never income. The app does not calculate interest or build a
/// repayment schedule. The manager enters each repayment split into principal
/// and interest exactly as the lender's statement shows. Principal reduces the
/// loan and is not an expense; interest is a finance cost in the P&L.
///
/// Outstanding is computed every time and never stored:
///   outstanding = principal (or opening balance) - non-voided principal repaid
/// All money is whole minor units (amount x 100), like BalanceMath.
class LoanSpec {
  final String id;

  /// Date received, or the entry date for an opening-balance loan.
  final DateTime dateReceived;

  /// Amount received, or the outstanding balance for an opening-balance loan.
  final int principalMinor;
  final bool voided;

  const LoanSpec({
    required this.id,
    required this.dateReceived,
    required this.principalMinor,
    this.voided = false,
  });
}

class RepaymentSpec {
  final String loanId;
  final DateTime date;
  final int principalMinor;
  final int interestMinor;
  final bool voided;

  const RepaymentSpec({
    required this.loanId,
    required this.date,
    this.principalMinor = 0,
    this.interestMinor = 0,
    this.voided = false,
  });
}

class RepaymentTotals {
  final int principalMinor;
  final int interestMinor;
  const RepaymentTotals({this.principalMinor = 0, this.interestMinor = 0});
}

class LoanMath {
  LoanMath._();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Principal repaid on [loanId] by repayments that are not voided, up to and
  /// including [asOf] when given.
  static int principalRepaid(
    String loanId,
    Iterable<RepaymentSpec> repayments, {
    DateTime? asOf,
  }) {
    var sum = 0;
    for (final r in repayments) {
      if (r.voided || r.loanId != loanId) continue;
      if (asOf != null && _day(r.date).isAfter(_day(asOf))) continue;
      sum += r.principalMinor;
    }
    return sum;
  }

  /// Interest paid on [loanId] by repayments that are not voided.
  static int interestPaid(String loanId, Iterable<RepaymentSpec> repayments) {
    var sum = 0;
    for (final r in repayments) {
      if (r.voided || r.loanId != loanId) continue;
      sum += r.interestMinor;
    }
    return sum;
  }

  /// What is still owed on a loan, never below zero. With [asOf] it is the
  /// balance on that date: zero before the loan existed, and only repayments
  /// made by that date count.
  static int outstanding(
    LoanSpec loan,
    Iterable<RepaymentSpec> repayments, {
    DateTime? asOf,
  }) {
    if (asOf != null && _day(loan.dateReceived).isAfter(_day(asOf))) return 0;
    final left =
        loan.principalMinor - principalRepaid(loan.id, repayments, asOf: asOf);
    return left < 0 ? 0 : left;
  }

  /// A loan with nothing outstanding is settled.
  static bool isSettled(
          LoanSpec loan, Iterable<RepaymentSpec> repayments) =>
      !loan.voided && outstanding(loan, repayments) == 0;

  /// Principal and interest paid on repayments dated from [from] to [to]
  /// inclusive, skipping voided repayments. Used by the report engine.
  static RepaymentTotals repaymentsBetween(
    Iterable<RepaymentSpec> repayments,
    DateTime from,
    DateTime to,
  ) {
    var principal = 0;
    var interest = 0;
    final f = _day(from);
    final t = _day(to);
    for (final r in repayments) {
      if (r.voided) continue;
      final d = _day(r.date);
      if (d.isBefore(f) || d.isAfter(t)) continue;
      principal += r.principalMinor;
      interest += r.interestMinor;
    }
    return RepaymentTotals(principalMinor: principal, interestMinor: interest);
  }

  // -------------------------------------------------------------------------
  // Checks. Each returns a plain-English problem, or null if it is fine.
  // -------------------------------------------------------------------------

  static String? validateNewLoan({
    required String lenderName,
    required String lenderType,
    required List<String> allowedLenderTypes,
    required DateTime dateReceived,
    required DateTime today,
    required double principal,
    required bool isOpeningBalance,
    required String receivedInto,
    double? interestRatePercent,
    int? termMonths,
  }) {
    if (lenderName.trim().isEmpty) return 'Enter the lender\'s name.';
    if (!allowedLenderTypes.contains(lenderType)) {
      return 'Choose the type of lender.';
    }
    if (_day(dateReceived).isAfter(_day(today))) {
      return 'The date cannot be in the future.';
    }
    if (dateReceived.year < 1990) return 'Check the date.';
    if (principal.isNaN || principal.isInfinite || principal <= 0) {
      return isOpeningBalance
          ? 'Enter the balance still owed, above zero.'
          : 'Enter the amount received, above zero.';
    }
    if (!isOpeningBalance && receivedInto.trim().isEmpty) {
      return 'Choose where the money was paid into.';
    }
    if (interestRatePercent != null &&
        (interestRatePercent.isNaN ||
            interestRatePercent.isInfinite ||
            interestRatePercent < 0)) {
      return 'The interest rate cannot be negative.';
    }
    if (termMonths != null && (termMonths < 1 || termMonths > 1200)) {
      return 'The term must be between 1 and 1200 months.';
    }
    return null;
  }

  static String? validateRepayment({
    required bool loanVoided,
    required int outstandingMinor,
    required int principalMinor,
    required int interestMinor,
    required DateTime date,
    required DateTime loanDate,
    required DateTime today,
    required String paymentMethod,
  }) {
    if (loanVoided) return 'This loan is voided.';
    if (principalMinor < 0 || interestMinor < 0) {
      return 'Amounts cannot be negative.';
    }
    if (principalMinor == 0 && interestMinor == 0) {
      return 'Enter a principal or an interest amount.';
    }
    if (_day(date).isAfter(_day(today))) {
      return 'The date cannot be in the future.';
    }
    if (_day(date).isBefore(_day(loanDate))) {
      return 'The repayment date cannot be before the loan date.';
    }
    if (paymentMethod.trim().isEmpty) return 'Choose how it was paid.';
    if (principalMinor > outstandingMinor) {
      return 'The principal cannot be more than the balance outstanding.';
    }
    return null;
  }

  static String? validateVoidLoan({
    required String reason,
    required bool isVoided,
    required bool hasActiveRepayments,
  }) {
    if (isVoided) return 'This loan is already voided.';
    if (hasActiveRepayments) {
      return 'Void this loan\'s repayments first, then void the loan.';
    }
    if (reason.trim().isEmpty) return 'Enter a reason for voiding.';
    return null;
  }

  static String? validateVoidRepayment({
    required String reason,
    required bool isVoided,
  }) {
    if (isVoided) return 'This repayment is already voided.';
    if (reason.trim().isEmpty) return 'Enter a reason for voiding.';
    return null;
  }
}
