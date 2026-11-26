import 'package:excel/excel.dart';

import 'report_data.dart';

/// Phase 10b: builds the financial report workbook (handoff section 6.3) from
/// a [ReportData]. Pure Dart apart from the `excel` package: no Hive, no
/// Flutter, so it can be tested directly.
///
/// Every figure comes from the engine's [ReportData], so this file never
/// recalculates business rules. Real formulas are used where they make the
/// file auditable: column totals (SUM), expense subtotals by type (SUMIFS),
/// the P&L and Cashflow arithmetic, and every Summary and Filing Figures line
/// (which point at the other sheets). Source figures that the engine works
/// out from several records (settlement adjustments, stock values, cash lines,
/// day and month buckets) are written as values.
///
/// The excel package writes formulas without calculated results. Excel and
/// Google Sheets calculate them when the file opens; some phone previewers
/// show those cells blank until it is opened in a spreadsheet app.
class ReportWorkbook {
  ReportWorkbook._();

  static const String sSummary = 'Summary';
  static const String sSales = 'Sales';
  static const String sExpenses = 'Expenses';
  static const String sPnl = 'P&L';
  static const String sCashflow = 'Cashflow';
  static const String sReceivables = 'Receivables';
  static const String sAssets = 'Fixed Assets & Depreciation';
  static const String sLoans = 'Loans';
  static const String sFiling = 'Filing Figures';
  static const String sUnmatched = 'Unmatched Balance Payments';
  static const String sNotes = 'Notes & Assumptions';

  /// A file name for the export, for example
  /// Financial_Report_2026-11-01_to_2026-11-30.xlsx
  static String fileName(ReportData d) =>
      'Financial_Report_${_iso(d.from)}_to_${_iso(d.to)}.xlsx';

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Builds the workbook and returns the .xlsx bytes.
  static List<int> build(
    ReportData d, {
    required String businessName,
    String address = '',
    String phone = '',
    String taxId = '',
    String currencySymbol = '',
  }) {
    final b = _Builder(
      d,
      businessName: businessName,
      address: address,
      phone: phone,
      taxId: taxId,
      currencySymbol: currencySymbol,
    );
    return b.build();
  }
}

// ---------------------------------------------------------------------------
// Styles
// ---------------------------------------------------------------------------

class _Styles {
  final CellStyle title;
  final CellStyle sub;
  final CellStyle heading;
  final CellStyle header;
  final CellStyle bold;
  final CellStyle italic;
  final CellStyle money;
  final CellStyle moneyBold;
  final CellStyle date;
  final CellStyle month;
  final CellStyle integer;
  final CellStyle warn;

  _Styles(String symbol)
      : title = CellStyle(bold: true, fontSize: 16),
        sub = CellStyle(italic: true),
        heading = CellStyle(
          bold: true,
          fontSize: 12,
          backgroundColorHex: ExcelColor.fromHexString('FFDDEBF7'),
        ),
        header = CellStyle(
          bold: true,
          fontColorHex: ExcelColor.white,
          backgroundColorHex: ExcelColor.fromHexString('FF1F4E78'),
        ),
        bold = CellStyle(bold: true),
        italic = CellStyle(italic: true),
        money = CellStyle(
          numberFormat: NumFormat.custom(formatCode: _moneyCode(symbol)),
          horizontalAlign: HorizontalAlign.Right,
        ),
        moneyBold = CellStyle(
          bold: true,
          numberFormat: NumFormat.custom(formatCode: _moneyCode(symbol)),
          horizontalAlign: HorizontalAlign.Right,
        ),
        date = CellStyle(
          numberFormat: NumFormat.custom(formatCode: 'dd-mmm-yyyy'),
          horizontalAlign: HorizontalAlign.Left,
        ),
        month = CellStyle(
          numberFormat: NumFormat.custom(formatCode: 'mmm yyyy'),
          horizontalAlign: HorizontalAlign.Left,
        ),
        integer = CellStyle(
          numberFormat: NumFormat.standard_3,
          horizontalAlign: HorizontalAlign.Right,
        ),
        warn = CellStyle(
          bold: true,
          fontColorHex: ExcelColor.fromHexString('FFC00000'),
        );

  static String _moneyCode(String symbol) {
    final s = symbol.replaceAll('"', '').trim();
    if (s.isEmpty) return '#,##0.00;[Red]-#,##0.00';
    return '"$s"#,##0.00;[Red]-"$s"#,##0.00';
  }
}

// ---------------------------------------------------------------------------
// Sheet helper
// ---------------------------------------------------------------------------

class _Sh {
  final String name;
  final Sheet sheet;
  final _Styles s;

  _Sh(Excel excel, this.name, this.s) : sheet = excel[name];

  static String col(int c) {
    var n = c;
    var out = '';
    do {
      out = String.fromCharCode(65 + n % 26) + out;
      n = n ~/ 26 - 1;
    } while (n >= 0);
    return out;
  }

  static String a1(int c, int r) => '${col(c)}${r + 1}';

  /// Reference to a cell from another sheet.
  String ref(int c, int r) => "'$name'!${a1(c, r)}";

  CellIndex _i(int c, int r) =>
      CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r);

  void text(int c, int r, String v, {CellStyle? style}) =>
      sheet.updateCell(_i(c, r), TextCellValue(v), cellStyle: style);

  void money(int c, int r, int minor, {CellStyle? style}) => sheet.updateCell(
      _i(c, r), DoubleCellValue(minor / 100), cellStyle: style ?? s.money);

  void count(int c, int r, int v, {CellStyle? style}) =>
      sheet.updateCell(_i(c, r), IntCellValue(v), cellStyle: style ?? s.integer);

  void date(int c, int r, DateTime d, {CellStyle? style}) => sheet.updateCell(
      _i(c, r), DateCellValue.fromDateTime(d), cellStyle: style ?? s.date);

  void formula(int c, int r, String f, {CellStyle? style}) =>
      sheet.updateCell(_i(c, r), FormulaCellValue(f),
          cellStyle: style ?? s.money);

  void headers(int r, List<String> names) {
    for (var c = 0; c < names.length; c++) {
      text(c, r, names[c], style: s.header);
    }
  }

  void widths(List<double> w) {
    for (var c = 0; c < w.length; c++) {
      sheet.setColumnWidth(c, w[c]);
    }
  }

  /// A SUM over rows [first]..[last] of column [c], or a plain zero when the
  /// block has no rows.
  void sum(int c, int r, int first, int last, {CellStyle? style}) {
    if (last < first) {
      money(c, r, 0, style: style ?? s.moneyBold);
    } else {
      formula(c, r, 'SUM(${a1(c, first)}:${a1(c, last)})',
          style: style ?? s.moneyBold);
    }
  }
}

/// Label in column A, amount in column B, optional note in column C.
class _Lines {
  final _Sh w;
  int row;
  _Lines(this.w, this.row);

  static String cell(int r) => 'B${r + 1}';

  int put(String label,
      {int? minor, String? f, bool bold = false, String? note}) {
    w.text(0, row, label, style: bold ? w.s.bold : null);
    if (f != null) {
      w.formula(1, row, f, style: bold ? w.s.moneyBold : w.s.money);
    } else if (minor != null) {
      w.money(1, row, minor, style: bold ? w.s.moneyBold : w.s.money);
    }
    if (note != null) w.text(2, row, note, style: w.s.italic);
    return row++;
  }

  void heading(String t) {
    w.text(0, row, t, style: w.s.heading);
    w.text(1, row, '', style: w.s.heading);
    row++;
  }

  void blank() => row++;

  void textLine(String t, {CellStyle? style}) {
    w.text(0, row, t, style: style);
    row++;
  }
}

// ---------------------------------------------------------------------------
// Builder
// ---------------------------------------------------------------------------

class _Refs {
  String salesRevenue = '0';
  String directSub = '0';
  String opSub = '0';
  String totalExpenses = '0';
  String faCharge = '0';
  String faGainLoss = '0';
  String faCarrying = '0';
  String loanInterest = '0';
  String loanEnd = '0';
  String receivables = '0';
  String cfBalancePayments = '0';
  String cfCashIn = '0';
  String cfCashOut = '0';
  String cfNet = '0';
  String pnlGross = '0';
  String pnlDirect = '0';
  String pnlDep = '0';
  String pnlGainLoss = '0';
  String pnlInterest = '0';
  String pnlNpbt = '0';
  String pnlTax = '';
  String pnlNpat = '0';
}

class _Builder {
  final ReportData d;
  final String businessName;
  final String address;
  final String phone;
  final String taxId;
  final String currencySymbol;

  late final Excel excel = Excel.createExcel();
  late final _Styles s = _Styles(currencySymbol);
  final _Refs refs = _Refs();

  _Builder(
    this.d, {
    required this.businessName,
    required this.address,
    required this.phone,
    required this.taxId,
    required this.currencySymbol,
  });

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static String _fmt(DateTime x) =>
      '${x.day.toString().padLeft(2, '0')} ${_months[x.month - 1]} ${x.year}';

  String get _periodText =>
      'Period: ${_fmt(d.from)} to ${_fmt(d.to)} (${d.periodLabel})';

  /// Title block shared by every sheet. Returns the first free row.
  int _title(_Sh w, String title) {
    w.text(0, 0, title, style: s.title);
    final parts = <String>[
      if (businessName.trim().isNotEmpty) businessName.trim(),
      if (address.trim().isNotEmpty) address.trim(),
      if (phone.trim().isNotEmpty) phone.trim(),
      if (taxId.trim().isNotEmpty) 'Tax ID: ${taxId.trim()}',
    ];
    w.text(0, 1, parts.join('  |  '), style: s.bold);
    w.text(0, 2, _periodText, style: s.sub);
    return 4;
  }

  List<int> build() {
    final order = <String>[
      ReportWorkbook.sSummary,
      ReportWorkbook.sSales,
      ReportWorkbook.sExpenses,
      ReportWorkbook.sPnl,
      ReportWorkbook.sCashflow,
      ReportWorkbook.sReceivables,
      ReportWorkbook.sAssets,
      ReportWorkbook.sLoans,
      ReportWorkbook.sFiling,
      if (d.unmatched.isNotEmpty) ReportWorkbook.sUnmatched,
      ReportWorkbook.sNotes,
    ];
    final sheets = {
      for (final n in order) n: _Sh(excel, n, s),
    };
    // The package starts with an empty default sheet; remove it.
    excel.delete('Sheet1');

    // Sheets that others point at are filled first; Summary last.
    _sales(sheets[ReportWorkbook.sSales]!);
    _expenses(sheets[ReportWorkbook.sExpenses]!);
    _assets(sheets[ReportWorkbook.sAssets]!);
    _loans(sheets[ReportWorkbook.sLoans]!);
    _receivables(sheets[ReportWorkbook.sReceivables]!);
    _cashflow(sheets[ReportWorkbook.sCashflow]!);
    _pnl(sheets[ReportWorkbook.sPnl]!);
    _filing(sheets[ReportWorkbook.sFiling]!);
    if (d.unmatched.isNotEmpty) {
      _unmatched(sheets[ReportWorkbook.sUnmatched]!);
    }
    _notes(sheets[ReportWorkbook.sNotes]!);
    _summary(sheets[ReportWorkbook.sSummary]!);

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('The workbook could not be created.');
    }
    return bytes;
  }

  // ---- Sales ---------------------------------------------------------------

  void _sales(_Sh w) {
    w.widths([14, 14, 24, 40, 16, 14, 16, 18, 18, 34]);
    var r = _title(w, 'Sales');
    w.text(0, r++,
        'Sale receipts only. Balance payments are cash, not sales. Revenue is '
        'what each receipt adds to sales.',
        style: s.sub);
    w.headers(r, [
      'Date', 'Receipt no.', 'Customer', 'Items', 'Receipt total', 'Discount',
      'Deposit', 'Balance at the time', 'Revenue counted', 'Status',
    ]);
    final first = ++r;
    for (final x in d.sales.rows) {
      w.date(0, r, x.date);
      w.text(1, r, x.code);
      w.text(2, r, x.customerName);
      w.text(3, r, x.itemsSummary);
      w.money(4, r, x.totalMinor);
      w.money(5, r, x.discountMinor);
      w.money(6, r, x.depositMinor);
      w.money(7, r, x.balanceAtTimeMinor);
      w.money(8, r, x.revenueMinor);
      w.text(9, r, x.status);
      r++;
    }
    final last = r - 1;
    w.text(0, r, 'Total (${d.sales.count} receipts)', style: s.bold);
    for (final c in [4, 5, 6, 8]) {
      w.sum(c, r, first, last);
    }
    refs.salesRevenue = w.ref(8, r);
    r += 2;

    w.text(0, r++, 'Sales by day', style: s.heading);
    w.headers(r++, ['Date', 'Receipts', 'Revenue', 'Discount', 'Deposit']);
    for (final x in d.sales.byDay) {
      w.date(0, r, x.key);
      w.count(1, r, x.count);
      w.money(2, r, x.revenueMinor);
      w.money(3, r, x.discountMinor);
      w.money(4, r, x.depositMinor);
      r++;
    }
    r++;
    w.text(0, r++, 'Sales by month', style: s.heading);
    w.headers(r++, ['Month', 'Receipts', 'Revenue', 'Discount', 'Deposit']);
    for (final x in d.sales.byMonth) {
      w.date(0, r, x.key, style: s.month);
      w.count(1, r, x.count);
      w.money(2, r, x.revenueMinor);
      w.money(3, r, x.discountMinor);
      w.money(4, r, x.depositMinor);
      r++;
    }
  }

  // ---- Expenses ------------------------------------------------------------

  static String _typeLabel(String group) {
    switch (group) {
      case 'direct':
        return 'Direct';
      case 'operating':
        return 'Operating';
      default:
        return 'Not in P&L';
    }
  }

  void _expenseRow(_Sh w, int r, ExpenseRowData e, {bool showVoidReason = false}) {
    w.date(0, r, e.date);
    w.text(1, r, e.categoryName);
    w.text(2, r, _typeLabel(e.group));
    w.money(3, r, e.amountMinor);
    w.text(4, r, e.paidFrom);
    w.text(5, r, e.vendor ?? '');
    if (e.inputVatMinor != null) w.money(6, r, e.inputVatMinor!);
    if (e.whtMinor != null) w.money(7, r, e.whtMinor!);
    w.text(8, r, e.description);
    w.text(9, r, e.enteredBy);
    if (showVoidReason) w.text(10, r, e.voidReason ?? '');
  }

  static const List<String> _expenseHeaders = [
    'Date', 'Category', 'Type', 'Amount', 'Paid from', 'Vendor',
    'Input VAT', 'WHT', 'Description', 'Entered by',
  ];

  void _expenses(_Sh w) {
    w.widths([14, 26, 14, 16, 18, 22, 14, 14, 36, 14, 28]);
    var r = _title(w, 'Expenses');
    w.text(0, r++, 'Direct and operating expenses that were not voided.',
        style: s.sub);
    w.headers(r, _expenseHeaders);
    final first = ++r;
    for (final e in d.expenses.rows) {
      _expenseRow(w, r, e);
      r++;
    }
    final last = r - 1;
    r++;

    final amount = last < first
        ? null
        : '${_Sh.a1(3, first)}:${_Sh.a1(3, last)}';
    final type = last < first ? null : '${_Sh.a1(2, first)}:${_Sh.a1(2, last)}';

    void subtotal(String label, String crit, int minor, {required bool direct}) {
      w.text(2, r, label, style: s.bold);
      if (amount == null) {
        w.money(3, r, 0, style: s.moneyBold);
      } else {
        w.formula(3, r, 'SUMIFS($amount,$type,"$crit")', style: s.moneyBold);
      }
      if (direct) {
        refs.directSub = w.ref(3, r);
      } else {
        refs.opSub = w.ref(3, r);
      }
      r++;
    }

    subtotal('Direct costs', 'Direct', d.expenses.directMinor, direct: true);
    subtotal('Operating expenses', 'Operating', d.expenses.operatingMinor,
        direct: false);
    w.text(2, r, 'Total expenses', style: s.bold);
    w.formula(3, r,
        '${_Sh.a1(3, r - 2)}+${_Sh.a1(3, r - 1)}',
        style: s.moneyBold);
    refs.totalExpenses = w.ref(3, r);
    r += 2;

    w.text(0, r++, 'Subtotals by category', style: s.heading);
    w.headers(r++, ['Category', 'Type', 'Entries', 'Amount']);
    for (final c in d.expenses.byCategory) {
      w.text(0, r, c.name);
      w.text(1, r, _typeLabel(c.group));
      w.count(2, r, c.count);
      w.money(3, r, c.amountMinor);
      r++;
    }
    r++;
    w.text(0, r++, 'Subtotals by month', style: s.heading);
    w.headers(r++, ['Month', 'Direct', 'Operating', 'Total']);
    for (final m in d.expenses.byMonth) {
      w.date(0, r, m.month, style: s.month);
      w.money(1, r, m.directMinor);
      w.money(2, r, m.operatingMinor);
      w.formula(3, r, '${_Sh.a1(1, r)}+${_Sh.a1(2, r)}');
      r++;
    }
    r++;

    w.text(0, r++,
        'Not in P&L (owner drawings, tax remittances). Not part of the expense total.',
        style: s.heading);
    w.headers(r, _expenseHeaders);
    final npFirst = ++r;
    for (final e in d.expenses.notInPnlRows) {
      _expenseRow(w, r, e);
      r++;
    }
    w.text(2, r, 'Not in P&L total', style: s.bold);
    w.sum(3, r, npFirst, r - 1);
    r += 2;

    if (d.expenses.voidedRows.isNotEmpty) {
      w.text(0, r++, 'Voided entries (listed only, never added up)',
          style: s.heading);
      w.headers(r, [..._expenseHeaders, 'Void reason']);
      r++;
      for (final e in d.expenses.voidedRows) {
        _expenseRow(w, r, e, showVoidReason: true);
        r++;
      }
    }
  }

  // ---- Receivables -----------------------------------------------------------

  void _receivables(_Sh w) {
    w.widths([14, 14, 26, 16, 16, 16, 12]);
    var r = _title(w, 'Receivables');
    w.text(0, r++,
        'Sales that still owed money on ${_fmt(d.to)}. Settled includes the '
        'deposit, later payments and write-offs.',
        style: s.sub);
    w.headers(r, [
      'Receipt no.', 'Date', 'Customer', 'Receipt total', 'Settled',
      'Outstanding', 'Age (days)',
    ]);
    final first = ++r;
    for (final x in d.receivables.rows) {
      w.text(0, r, x.code);
      w.date(1, r, x.issuedAt);
      w.text(2, r, x.customerName);
      w.money(3, r, x.totalMinor);
      w.money(4, r, x.settledMinor);
      w.money(5, r, x.outstandingMinor);
      w.count(6, r, x.ageDays);
      r++;
    }
    final last = r - 1;
    w.text(0, r, 'Total outstanding', style: s.bold);
    for (final c in [3, 4, 5]) {
      w.sum(c, r, first, last);
    }
    refs.receivables = w.ref(5, r);
  }

  // ---- Fixed assets ------------------------------------------------------------

  void _assets(_Sh w) {
    w.widths([28, 24, 14, 16, 18, 16, 18, 16, 18, 20, 20, 16]);
    var r = _title(w, 'Fixed Assets & Depreciation');
    w.text(0, r++,
        'Register as at ${_fmt(d.to)}. Book depreciation only; your accountant '
        'may use different tax allowances.',
        style: s.sub);
    w.headers(r, [
      'Asset', 'Category', 'Purchase date', 'Cost', 'Method',
      'Owned before the app', 'Depreciation at start', 'Charge for the period',
      'Depreciation at end', 'Net book value (or when retired)',
      'Book value at end', 'Retired',
    ]);
    final first = ++r;
    for (final x in d.fixedAssets.rows) {
      w.text(0, r, x.name);
      w.text(1, r, x.categoryName);
      w.date(2, r, x.purchaseDate);
      w.money(3, r, x.costMinor);
      w.text(4, r, x.method);
      w.text(5, r, x.isOpeningBalance ? 'Yes' : 'No');
      w.money(6, r, x.accumulatedAtStartMinor);
      w.money(7, r, x.chargeMinor);
      w.money(8, r, x.accumulatedAtEndMinor);
      w.money(9, r, x.netBookValueMinor);
      w.money(10, r, x.carryingMinor);
      if (x.retiredDate != null) w.date(11, r, x.retiredDate!);
      r++;
    }
    final last = r - 1;
    w.text(0, r, 'Totals', style: s.bold);
    for (final c in [3, 6, 7, 8, 9, 10]) {
      w.sum(c, r, first, last);
    }
    refs.faCharge = w.ref(7, r);
    refs.faCarrying = w.ref(10, r);
    r += 2;

    w.text(0, r++, 'Additions in the period', style: s.heading);
    w.headers(r, ['Asset', '', 'Purchase date', 'Cost', 'Paid with']);
    final aFirst = ++r;
    for (final a in d.fixedAssets.additions) {
      w.text(0, r, a.name);
      w.date(2, r, a.purchaseDate);
      w.money(3, r, a.costMinor);
      w.text(4, r, a.isOpeningBalance ? 'Opening balance (no cash)' : a.paymentMethod);
      r++;
    }
    w.text(0, r, 'Total additions', style: s.bold);
    w.sum(3, r, aFirst, r - 1);
    r += 2;

    w.text(0, r++, 'Disposals in the period', style: s.heading);
    w.headers(r, [
      'Asset', '', 'Date', 'Proceeds', 'Book value at disposal', 'Gain or loss',
    ]);
    final dFirst = ++r;
    for (final x in d.fixedAssets.disposals) {
      w.text(0, r, x.name);
      w.date(2, r, x.date);
      w.money(3, r, x.proceedsMinor);
      w.money(4, r, x.nbvAtDisposalMinor);
      w.money(5, r, x.gainLossMinor);
      r++;
    }
    w.text(0, r, 'Total disposals', style: s.bold);
    for (final c in [3, 4, 5]) {
      w.sum(c, r, dFirst, r - 1);
    }
    refs.faGainLoss = w.ref(5, r);
  }

  // ---- Loans ---------------------------------------------------------------------

  void _loans(_Sh w) {
    w.widths([26, 16, 18, 18, 16, 18, 18, 16, 14]);
    var r = _title(w, 'Loans');
    w.text(0, r++,
        'Principal repaid reduces the loan and is not an expense. Interest paid '
        'is a finance cost.',
        style: s.sub);
    w.headers(r, [
      'Lender', 'Type', 'Existed before the app', 'Balance at start', 'Received',
      'Principal repaid', 'Balance at end', 'Interest paid', 'Status',
    ]);
    final first = ++r;
    for (final x in d.loans.rows) {
      w.text(0, r, x.lenderName);
      w.text(1, r, x.lenderType);
      w.text(2, r, x.isOpeningBalance ? 'Yes' : 'No');
      w.money(3, r, x.balanceAtStartMinor);
      w.money(4, r, x.receivedMinor);
      w.money(5, r, x.principalRepaidMinor);
      w.money(6, r, x.balanceAtEndMinor);
      w.money(7, r, x.interestPaidMinor);
      w.text(8, r, x.settled ? 'Settled' : 'Active');
      r++;
    }
    final last = r - 1;
    w.text(0, r, 'Totals', style: s.bold);
    for (final c in [3, 4, 5, 6, 7]) {
      w.sum(c, r, first, last);
    }
    refs.loanEnd = w.ref(6, r);
    refs.loanInterest = w.ref(7, r);
    r += 2;

    w.text(0, r++, 'Repayments in the period', style: s.heading);
    w.headers(r, ['Date', 'Lender', 'Principal', 'Interest', 'Paid with', 'Note']);
    final rFirst = ++r;
    for (final x in d.loans.repayments) {
      w.date(0, r, x.date);
      w.text(1, r, x.lenderName);
      w.money(2, r, x.principalMinor);
      w.money(3, r, x.interestMinor);
      w.text(4, r, x.paymentMethod);
      w.text(5, r, x.note);
      r++;
    }
    w.text(0, r, 'Totals', style: s.bold);
    for (final c in [2, 3]) {
      w.sum(c, r, rFirst, r - 1);
    }
  }

  // ---- Cashflow ----------------------------------------------------------------

  void _cashflow(_Sh w) {
    w.widths([52, 20, 20, 20]);
    final c = d.cashflow;
    final l = _Lines(w, _title(w, 'Cashflow'));
    l.textLine('Cash basis: money counted on the day it moved.', style: s.sub);
    if (c.openingCashAfterPeriodStart) {
      l.textLine(
          'The opening cash date is after this period starts, so the opening '
          'balance could not be worked out properly.',
          style: s.warn);
    }
    final open = l.put('Opening cash balance', minor: c.openingBalanceMinor, bold: true);
    l.blank();

    l.heading('Operating');
    final dep = l.put('Cash from sale deposits', minor: c.salesDepositsMinor);
    final bal = l.put('Balance payments received', minor: c.balancePaymentsMinor);
    refs.cfBalancePayments = w.ref(1, bal);
    final tin = l.put('Total operating cash in',
        f: '${_Lines.cell(dep)}+${_Lines.cell(bal)}', bold: true);
    final exp = l.put('Expenses paid (direct and operating)', minor: c.expensesPaidMinor);
    final tax = l.put('Taxes remitted', minor: c.taxesRemittedMinor);
    final tout = l.put('Total operating cash out',
        f: '${_Lines.cell(exp)}+${_Lines.cell(tax)}', bold: true);
    final netOp = l.put('Net cash from operations',
        f: '${_Lines.cell(tin)}-${_Lines.cell(tout)}', bold: true);
    l.blank();

    l.heading('Investing');
    final pur = l.put('Asset purchases', minor: c.assetPurchasesMinor);
    final pro = l.put('Proceeds from asset disposals', minor: c.disposalProceedsMinor);
    final netInv = l.put('Net cash from investing',
        f: '${_Lines.cell(pro)}-${_Lines.cell(pur)}', bold: true);
    l.blank();

    l.heading('Financing');
    final rec = l.put('Loans received', minor: c.loansReceivedMinor);
    final pri = l.put('Loan principal repaid', minor: c.principalRepaidMinor);
    final intr = l.put('Interest paid', minor: c.interestPaidMinor);
    final drw = l.put('Owner drawings', minor: c.ownerDrawingsMinor);
    final netFin = l.put('Net cash from financing',
        f: '${_Lines.cell(rec)}-${_Lines.cell(pri)}-${_Lines.cell(intr)}-${_Lines.cell(drw)}',
        bold: true);
    l.blank();

    final change = l.put('Net change in cash',
        f: '${_Lines.cell(netOp)}+${_Lines.cell(netInv)}+${_Lines.cell(netFin)}',
        bold: true);
    l.put('Closing cash balance',
        f: '${_Lines.cell(open)}+${_Lines.cell(change)}', bold: true);
    l.blank();

    l.heading('Totals');
    final cin = l.put('Total cash in',
        f: '${_Lines.cell(tin)}+${_Lines.cell(pro)}+${_Lines.cell(rec)}');
    final cout = l.put('Total cash out',
        f: '${_Lines.cell(tout)}+${_Lines.cell(pur)}+${_Lines.cell(pri)}+${_Lines.cell(intr)}+${_Lines.cell(drw)}');
    final net = l.put('Net cash movement',
        f: '${_Lines.cell(cin)}-${_Lines.cell(cout)}', bold: true);
    refs.cfCashIn = w.ref(1, cin);
    refs.cfCashOut = w.ref(1, cout);
    refs.cfNet = w.ref(1, net);
    l.blank();

    var r = l.row;
    w.text(0, r++, 'By payment method', style: s.heading);
    w.headers(r++, ['Method', 'Cash in', 'Cash out', 'Net']);
    for (final m in c.byMethod) {
      w.text(0, r, m.method);
      w.money(1, r, m.inMinor);
      w.money(2, r, m.outMinor);
      w.formula(3, r, '${_Sh.a1(1, r)}-${_Sh.a1(2, r)}');
      r++;
    }
  }

  // ---- P&L -------------------------------------------------------------------

  void _pnl(_Sh w) {
    w.widths([58, 20, 44]);
    final p = d.pnl;
    final l = _Lines(w, _title(w, 'P&L'));
    l.textLine(
        'Basis: sales are counted once on the original receipt date at full '
        'value; costs when incurred. Full wording is on Notes & Assumptions.',
        style: s.sub);
    l.blank();

    final rev = l.put('Revenue (sales)', f: refs.salesRevenue, bold: true);
    final adj = l.put('Less: settlement adjustments (write-offs)',
        minor: p.settlementAdjustmentsMinor);
    int? open;
    int? close;
    if (p.stockAdjusted) {
      open = l.put('Opening stock', minor: p.openingStockMinor ?? 0);
    }
    final pur = l.put('Direct purchases in the period', f: refs.directSub);
    if (p.stockAdjusted) {
      close = l.put('Less: closing stock', minor: p.closingStockMinor ?? 0);
    }
    final direct = l.put('Less: direct costs',
        f: p.stockAdjusted
            ? '${_Lines.cell(open!)}+${_Lines.cell(pur)}-${_Lines.cell(close!)}'
            : _Lines.cell(pur),
        bold: true,
        note: p.stockAdjusted
            ? 'Opening stock + purchases - closing stock'
            : 'No stock count, so direct costs equal purchases');
    final gp = l.put('Gross profit',
        f: '${_Lines.cell(rev)}-${_Lines.cell(adj)}-${_Lines.cell(direct)}',
        bold: true);
    final opex = l.put('Less: operating expenses (excluding depreciation)',
        f: refs.opSub);
    final opbd = l.put('Operating profit before depreciation',
        f: '${_Lines.cell(gp)}-${_Lines.cell(opex)}', bold: true);
    final dep = l.put('Less: depreciation', f: refs.faCharge);
    final gl = l.put('Add or less: gain or loss on asset disposal',
        f: refs.faGainLoss);
    final op = l.put('Operating profit',
        f: '${_Lines.cell(opbd)}-${_Lines.cell(dep)}+${_Lines.cell(gl)}',
        bold: true);
    final intr = l.put('Less: interest paid (finance cost)', f: refs.loanInterest);
    final npbt = l.put('Net profit before tax',
        f: '${_Lines.cell(op)}-${_Lines.cell(intr)}', bold: true);

    var npat = npbt;
    if (d.filing.estimatedTaxMinor != null) {
      final tax = l.put('Less: estimated tax (an estimate only)',
          minor: p.estimatedTaxMinor);
      npat = l.put('Net profit after tax',
          f: '${_Lines.cell(npbt)}-${_Lines.cell(tax)}', bold: true);
      refs.pnlTax = w.ref(1, tax);
    }

    refs.pnlGross = w.ref(1, gp);
    refs.pnlDirect = w.ref(1, direct);
    refs.pnlDep = w.ref(1, dep);
    refs.pnlGainLoss = w.ref(1, gl);
    refs.pnlInterest = w.ref(1, intr);
    refs.pnlNpbt = w.ref(1, npbt);
    refs.pnlNpat = w.ref(1, npat);

    l.blank();
    l.heading('Check against the app');
    final app = l.put('Net profit before tax as worked out by the app',
        minor: p.netProfitBeforeTaxMinor);
    l.put('Difference (should be 0.00)',
        f: '${_Lines.cell(npbt)}-${_Lines.cell(app)}');
  }

  // ---- Filing figures ----------------------------------------------------------

  void _filing(_Sh w) {
    w.widths([58, 20, 44]);
    final f = d.filing;
    final l = _Lines(w, _title(w, 'Filing Figures'));
    l.textLine(FilingSection.disclaimer, style: s.warn);
    l.blank();

    l.put('Turnover', f: refs.salesRevenue);
    l.put('Direct costs', f: refs.pnlDirect);
    l.put('Operating expenses', f: refs.opSub);
    l.put('Book depreciation', f: refs.pnlDep);
    l.put('Interest paid', f: refs.pnlInterest);
    l.put('Gain or loss on disposals', f: refs.pnlGainLoss);
    l.put('Net profit before tax', f: refs.pnlNpbt, bold: true);
    l.blank();

    l.heading('VAT');
    if (f.vatEnabled) {
      l.textLine('VAT rate used: ${f.vatRatePercent}%');
      final col = l.put('VAT collected (receipt totals taken to include VAT)',
          minor: f.vatCollectedMinor ?? 0);
      final inp = l.put('Input VAT paid (from expenses)',
          minor: f.inputVatPaidMinor);
      l.put('VAT payable',
          f: '${_Lines.cell(col)}-${_Lines.cell(inp)}', bold: true);
    } else {
      l.put('Input VAT paid (from expenses)', minor: f.inputVatPaidMinor,
          note: 'VAT is switched off in settings');
    }
    l.blank();

    if (f.estimatedTaxMinor != null) {
      l.put('Estimated tax (an estimate only)', minor: f.estimatedTaxMinor);
      l.blank();
    }

    l.heading('Position at the end of the period');
    l.put('Receivables', f: refs.receivables);
    if (f.closingStockMinor != null) {
      l.put('Closing stock', minor: f.closingStockMinor);
    }
    l.put('Asset net book value', f: refs.faCarrying);
    l.put('Loans outstanding', f: refs.loanEnd);
  }

  // ---- Unmatched -----------------------------------------------------------------

  void _unmatched(_Sh w) {
    w.widths([14, 14, 24, 16, 46, 40, 24, 50, 12]);
    var r = _title(w, 'Unmatched Balance Payments');
    w.text(0, r++,
        'Old receipts that look like balance payments but could not be linked '
        'to a sale. Until linked they stay in Sales and are not taken off '
        'Receivables. Link them on the Unmatched Balance Payments screen.',
        style: s.sub);
    w.headers(r, [
      'Receipt no.', 'Date', 'Customer', 'Money received', 'Why it needs a look',
      'Text read from the receipt', 'Numbers found', 'Possible sales', 'In period',
    ]);
    final first = ++r;
    for (final x in d.unmatched.rows) {
      w.text(0, r, x.code);
      w.date(1, r, x.date);
      w.text(2, r, x.customerName);
      w.money(3, r, x.paidMinor);
      w.text(4, r, x.reason);
      w.text(5, r, x.textSnippet);
      w.text(6, r, x.referencesFound);
      w.text(7, r, x.suggestions.join('; '));
      w.text(8, r, x.inPeriod ? 'Yes' : 'No');
      r++;
    }
    w.text(0, r, 'Total', style: s.bold);
    w.sum(3, r, first, r - 1);
  }

  // ---- Notes ----------------------------------------------------------------------

  void _notes(_Sh w) {
    w.widths([120]);
    var r = _title(w, 'Notes & Assumptions');
    final n = d.notes;
    if (n.generatedAt != null) {
      w.text(0, r++, 'Generated: ${_fmt(n.generatedAt!)} '
          '${n.generatedAt!.hour.toString().padLeft(2, '0')}:'
          '${n.generatedAt!.minute.toString().padLeft(2, '0')}');
    }
    if (n.appVersion.isNotEmpty) w.text(0, r++, 'App version: ${n.appVersion}');
    w.text(0, r++, _periodText);
    r++;

    w.text(0, r++, 'How figures are recognised', style: s.heading);
    for (final line in n.basis) {
      w.text(0, r++, '- $line');
    }
    r++;

    if (n.notes.isNotEmpty) {
      w.text(0, r++, 'Notes for this report', style: s.heading);
      for (final line in n.notes) {
        w.text(0, r++, '- $line');
      }
      r++;
    }

    w.text(0, r++, 'About the formulas', style: s.heading);
    for (final line in const [
      'Column totals, expense subtotals, the P&L, the Cashflow arithmetic, '
          'Filing Figures and the Summary are live formulas, so they can be '
          'checked cell by cell.',
      'The file stores formulas without calculated results. Excel and Google '
          'Sheets calculate them when the file is opened. Some phone file '
          'previewers show those cells blank until the file is opened in a '
          'spreadsheet app. The figures in the app preview are the same.',
      'Cells with no formula hold figures the app worked out from your '
          'records.',
    ]) {
      w.text(0, r++, '- $line');
    }
  }

  // ---- Summary --------------------------------------------------------------------

  void _summary(_Sh w) {
    w.widths([52, 22, 34]);
    final sm = d.summary;
    final l = _Lines(w, _title(w, 'Summary'));
    if (sm.unmatchedCount > 0) {
      l.textLine(
          '${sm.unmatchedCount} old balance receipt(s) are not linked to a '
          'sale. See the Unmatched Balance Payments sheet.',
          style: s.warn);
      l.blank();
    }

    l.heading('Sales and profit');
    l.put('Total sales', f: refs.salesRevenue);
    l.put('Balance payments collected', f: refs.cfBalancePayments,
        note: 'Cash received, not added to sales');
    l.put('Total expenses (direct and operating)', f: refs.totalExpenses);
    l.put('Gross profit', f: refs.pnlGross);
    l.put('Depreciation', f: refs.pnlDep);
    l.put('Interest paid', f: refs.pnlInterest);
    l.put('Net profit before tax', f: refs.pnlNpbt, bold: true);
    if (d.filing.estimatedTaxMinor != null) {
      l.put('Estimated tax (an estimate only)', f: refs.pnlTax);
      l.put('Net profit after tax', f: refs.pnlNpat, bold: true);
    }
    l.blank();

    l.heading('Cash');
    l.put('Cash in', f: refs.cfCashIn);
    l.put('Cash out', f: refs.cfCashOut);
    l.put('Net cash movement', f: refs.cfNet, bold: true);
    l.blank();

    l.heading('Position at ${_fmt(d.to)}');
    l.put('Outstanding receivables', f: refs.receivables);
    l.put('Asset net book value', f: refs.faCarrying);
    l.put('Loans outstanding', f: refs.loanEnd);
    l.blank();

    if (sm.topCategories.isNotEmpty) {
      l.heading('Top expense categories');
      for (final c in sm.topCategories) {
        l.put(c.name, minor: c.amountMinor);
      }
    }
  }
}
