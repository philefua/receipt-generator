import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:intl/intl.dart';

import '../models/expense.dart';

/// Builds the expense report that is pasted into tab `3_Expense_Ledger` of
/// the Printiverse financial workbook.
///
/// One sheet, 14 columns (A to N) in exactly the order and wording of the
/// ledger's header row. Dates are real Excel dates (not text). Voided
/// entries are never exported: pass in
/// `AppStateController.exportableExpenses`.
///
/// Column J (Total Cash Paid) is exported as a plain number so the file is
/// readable on its own; the workbook calculates its own J (Net + VAT - WHT),
/// so a loader should leave the workbook's column J alone.
class ExpenseExportService {
  ExpenseExportService._();

  static const String sheetName = 'Expenses';

  /// Row 5 of `3_Expense_Ledger`, character for character.
  static const List<String> headers = [
    'Date',
    'Voucher / Ref #',
    'Vendor / Payee',
    'Description & Qty',
    'Cost Type',
    'Expense Category',
    'Net Expense (Excl. VAT)',
    'Input VAT Paid',
    'WHT Deducted',
    'Total Cash Paid',
    'Payment Account',
    'Receipt / Audit Status',
    'Recorded By',
    'Notes / Asset Tag (CapEx)',
  ];

  /// e.g. expense_report_20261121_143000.xlsx
  static String fileName([DateTime? now]) {
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(now ?? DateTime.now());
    return 'expense_report_$stamp.xlsx';
  }

  static Future<Uint8List> buildExcelBytes(List<Expense> expenses) async {
    final workbook = xls.Excel.createExcel();
    final sheet = workbook[sheetName];
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheetName) {
      workbook.delete(defaultSheet);
    }

    sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());

    for (final e in expenses) {
      sheet.appendRow([
        xls.DateCellValue.fromDateTime(e.date),
        xls.TextCellValue(e.voucher),
        xls.TextCellValue(e.vendor),
        xls.TextCellValue(e.description),
        xls.TextCellValue(e.costType),
        xls.TextCellValue(e.category),
        xls.DoubleCellValue(e.netAmount),
        xls.DoubleCellValue(e.inputVat),
        xls.DoubleCellValue(e.whtDeducted),
        xls.DoubleCellValue(e.totalCashPaid),
        xls.TextCellValue(e.paymentAccount),
        xls.TextCellValue(e.receiptStatus),
        e.recordedBy.isEmpty ? null : xls.TextCellValue(e.recordedBy),
        e.notes.isEmpty ? null : xls.TextCellValue(e.notes),
      ]);
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw Exception('Failed to encode Excel file.');
    }
    return Uint8List.fromList(bytes);
  }
}