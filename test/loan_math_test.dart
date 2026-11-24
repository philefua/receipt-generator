import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_generator/features/finance/loan_math.dart';

int m(num naira) => (naira * 100).round();

LoanSpec loan({num principal = 500000, DateTime? date, bool voided = false}) =>
    LoanSpec(
      id: 'L1',
      dateReceived: date ?? DateTime(2026, 1, 10),
      principalMinor: m(principal),
      voided: voided,
    );

RepaymentSpec pay(num principal, num interest, DateTime date,
        {String loanId = 'L1', bool voided = false}) =>
    RepaymentSpec(
      loanId: loanId,
      date: date,
      principalMinor: m(principal),
      interestMinor: m(interest),
      voided: voided,
    );

void main() {
  final today = DateTime(2026, 11, 24);
  final lenders = ['bank', 'individual', 'cooperative', 'other'];

  group('outstanding balance', () {
    test('a new loan owes its full principal', () {
      expect(LoanMath.outstanding(loan(), const []), m(500000));
    });

    test('principal repayments reduce it, interest does not', () {
      final rs = [
        pay(100000, 20000, DateTime(2026, 2, 10)),
        pay(50000, 15000, DateTime(2026, 3, 10)),
      ];
      expect(LoanMath.outstanding(loan(), rs), m(350000));
      expect(LoanMath.interestPaid('L1', rs), m(35000));
    });

    test('voided repayments are ignored', () {
      final rs = [
        pay(100000, 0, DateTime(2026, 2, 10)),
        pay(200000, 0, DateTime(2026, 3, 10), voided: true),
      ];
      expect(LoanMath.outstanding(loan(), rs), m(400000));
    });

    test('other loans\' repayments are ignored', () {
      final rs = [pay(100000, 0, DateTime(2026, 2, 10), loanId: 'L2')];
      expect(LoanMath.outstanding(loan(), rs), m(500000));
    });

    test('never below zero', () {
      expect(LoanMath.outstanding(loan(principal: 1000), [pay(2000, 0, DateTime(2026, 2, 1))]), 0);
    });

    test('settled when nothing is left', () {
      final rs = [pay(500000, 0, DateTime(2026, 6, 1))];
      expect(LoanMath.isSettled(loan(), rs), isTrue);
      expect(LoanMath.isSettled(loan(), const []), isFalse);
    });

    test('a voided loan is never called settled', () {
      expect(LoanMath.isSettled(loan(voided: true), [pay(500000, 0, DateTime(2026, 6, 1))]), isFalse);
    });

    test('balance as at a date counts only repayments made by then', () {
      final rs = [
        pay(100000, 0, DateTime(2026, 2, 10)),
        pay(100000, 0, DateTime(2026, 4, 10)),
      ];
      expect(LoanMath.outstanding(loan(), rs, asOf: DateTime(2026, 3, 1)), m(400000));
      expect(LoanMath.outstanding(loan(), rs, asOf: DateTime(2026, 4, 10)), m(300000));
    });

    test('balance before the loan existed is zero', () {
      expect(LoanMath.outstanding(loan(), const [], asOf: DateTime(2025, 12, 31)), 0);
    });
  });

  group('period totals', () {
    final rs = [
      pay(100000, 20000, DateTime(2026, 2, 10)),
      pay(50000, 15000, DateTime(2026, 3, 10)),
      pay(30000, 5000, DateTime(2026, 3, 20), voided: true),
      pay(10000, 1000, DateTime(2026, 5, 1)),
    ];

    test('sums principal and interest inside the range, inclusive', () {
      final t = LoanMath.repaymentsBetween(rs, DateTime(2026, 2, 10), DateTime(2026, 3, 10));
      expect(t.principalMinor, m(150000));
      expect(t.interestMinor, m(35000));
    });

    test('skips voided repayments', () {
      final t = LoanMath.repaymentsBetween(rs, DateTime(2026, 3, 11), DateTime(2026, 3, 31));
      expect(t.principalMinor, 0);
      expect(t.interestMinor, 0);
    });
  });

  group('new loan rules', () {
    String? check({
      String name = 'First Bank',
      String type = 'bank',
      DateTime? date,
      double principal = 500000,
      bool opening = false,
      String into = 'Bank transfer',
      double? rate,
      int? term,
    }) =>
        LoanMath.validateNewLoan(
          lenderName: name,
          lenderType: type,
          allowedLenderTypes: lenders,
          dateReceived: date ?? DateTime(2026, 1, 10),
          today: today,
          principal: principal,
          isOpeningBalance: opening,
          receivedInto: into,
          interestRatePercent: rate,
          termMonths: term,
        );

    test('accepts a good loan', () => expect(check(), isNull));
    test('accepts an old date', () => expect(check(date: DateTime(2022, 5, 1)), isNull));
    test('refuses a future date', () => expect(check(date: DateTime(2026, 12, 1)), isNotNull));
    test('refuses no lender', () => expect(check(name: ' '), isNotNull));
    test('refuses an unknown type', () => expect(check(type: 'friend'), isNotNull));
    test('refuses zero', () => expect(check(principal: 0), isNotNull));
    test('needs somewhere it was paid into', () => expect(check(into: ''), isNotNull));
    test('opening balance needs no account', () => expect(check(opening: true, into: ''), isNull));
    test('refuses a negative rate', () => expect(check(rate: -1), isNotNull));
    test('refuses a silly term', () => expect(check(term: 0), isNotNull));
  });

  group('repayment rules', () {
    String? check({
      bool voided = false,
      num outstanding = 100000,
      num principal = 20000,
      num interest = 1000,
      DateTime? date,
      String method = 'Cash',
    }) =>
        LoanMath.validateRepayment(
          loanVoided: voided,
          outstandingMinor: m(outstanding),
          principalMinor: m(principal),
          interestMinor: m(interest),
          date: date ?? DateTime(2026, 6, 1),
          loanDate: DateTime(2026, 1, 10),
          today: today,
          paymentMethod: method,
        );

    test('accepts a good repayment', () => expect(check(), isNull));
    test('accepts paying off exactly the balance', () => expect(check(principal: 100000), isNull));
    test('accepts interest only', () => expect(check(principal: 0), isNull));
    test('accepts interest after the loan is settled', () => expect(check(outstanding: 0, principal: 0), isNull));
    test('refuses both zero', () => expect(check(principal: 0, interest: 0), isNotNull));
    test('refuses principal above the balance', () => expect(check(principal: 100000.01), isNotNull));
    test('refuses a voided loan', () => expect(check(voided: true), isNotNull));
    test('refuses a negative amount', () => expect(check(interest: -1), isNotNull));
    test('refuses a date before the loan', () => expect(check(date: DateTime(2026, 1, 9)), isNotNull));
    test('refuses a future date', () => expect(check(date: DateTime(2026, 12, 1)), isNotNull));
    test('needs a payment method', () => expect(check(method: ' '), isNotNull));
  });

  group('void rules', () {
    test('a loan with live repayments cannot be voided', () {
      expect(LoanMath.validateVoidLoan(reason: 'x', isVoided: false, hasActiveRepayments: true), isNotNull);
    });
    test('a loan needs a reason', () {
      expect(LoanMath.validateVoidLoan(reason: ' ', isVoided: false, hasActiveRepayments: false), isNotNull);
    });
    test('a loan can be voided', () {
      expect(LoanMath.validateVoidLoan(reason: 'Entered twice', isVoided: false, hasActiveRepayments: false), isNull);
    });
    test('a loan cannot be voided twice', () {
      expect(LoanMath.validateVoidLoan(reason: 'x', isVoided: true, hasActiveRepayments: false), isNotNull);
    });
    test('a repayment needs a reason', () {
      expect(LoanMath.validateVoidRepayment(reason: '', isVoided: false), isNotNull);
    });
    test('a repayment can be voided', () {
      expect(LoanMath.validateVoidRepayment(reason: 'Wrong split', isVoided: false), isNull);
    });
    test('a repayment cannot be voided twice', () {
      expect(LoanMath.validateVoidRepayment(reason: 'x', isVoided: true), isNotNull);
    });
  });
}
