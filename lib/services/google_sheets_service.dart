import 'package:csv/csv.dart';

import 'google_drive_service.dart';

/// A single product row read from the manager's product Sheet.
class SheetProductRow {
  final String name;
  final double price;

  const SheetProductRow({required this.name, required this.price});
}

/// Result wrapper for product-sheet read operations.
class SheetsOperationResult {
  final bool success;
  final String message;
  final List<SheetProductRow> products;

  const SheetsOperationResult({
    required this.success,
    required this.message,
    this.products = const [],
  });

  factory SheetsOperationResult.ok(
    List<SheetProductRow> products, [
    String message = 'OK',
  ]) =>
      SheetsOperationResult(success: true, message: message, products: products);

  factory SheetsOperationResult.fail(String message) =>
      SheetsOperationResult(success: false, message: message, products: const []);
}

/// Reads product data from the manager's product Sheet — a native Google
/// Sheet this app itself created in their Drive (see
/// GoogleDriveService.createProductSheet). Reading happens via Drive's
/// CSV export endpoint, not the Sheets API, so this entire feature
/// operates under the single drive.file scope.
///
/// Expected layout (first row may optionally be a header row, which is
/// automatically skipped if its price column isn't a valid number):
///   Column A: Product Name
///   Column B: Price
class GoogleSheetsService {
  GoogleSheetsService._internal();

  static final GoogleSheetsService instance = GoogleSheetsService._internal();

  Future<SheetsOperationResult> fetchProducts({
    required String fileId,
  }) async {
    if (fileId.trim().isEmpty) {
      return SheetsOperationResult.fail(
        'No product Sheet has been created yet.',
      );
    }

    if (!GoogleDriveService.instance.isSignedIn) {
      return SheetsOperationResult.fail(
        'Not signed in to Google. Connect a Google account first.',
      );
    }

    try {
      final exportResult =
          await GoogleDriveService.instance.exportProductSheetAsCsv(fileId);

      if (!exportResult.success || exportResult.csvContent == null) {
        return SheetsOperationResult.fail(exportResult.message);
      }

      final rows = const CsvToListConverter(eol: '\n')
          .convert(exportResult.csvContent!, shouldParseNumbers: false);

      if (rows.isEmpty) {
        return SheetsOperationResult.fail(
          'The product Sheet appears to be empty.',
        );
      }

      final List<SheetProductRow> products = [];
      for (final row in rows) {
        if (row.isEmpty) continue;

        final name = row.isNotEmpty ? row[0]?.toString().trim() ?? '' : '';
        final priceRaw = row.length > 1 ? row[1]?.toString().trim() ?? '' : '';

        if (name.isEmpty) continue;

        final price = double.tryParse(priceRaw);
        if (price == null) {
          // Skips the header row ("Product Name" / "Price") or any
          // malformed row automatically, without failing the whole sync.
          continue;
        }

        products.add(SheetProductRow(name: name, price: price));
      }

      if (products.isEmpty) {
        return SheetsOperationResult.fail(
          'No valid product rows found in the Sheet.',
        );
      }

      return SheetsOperationResult.ok(
        products,
        '${products.length} product(s) read from Sheet.',
      );
    } catch (e) {
      return SheetsOperationResult.fail('Sheet read failed: $e');
    }
  }
}