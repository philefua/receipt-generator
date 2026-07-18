import 'package:googleapis/sheets/v4.dart' as sheets;
import 'package:http/http.dart' as http;

import 'google_drive_service.dart';

/// A single product row read from the manager's Google Sheet.
class SheetProductRow {
  final String name;
  final double price;

  const SheetProductRow({required this.name, required this.price});
}

/// Result wrapper for Sheets operations.
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

/// Reads product data from a Google Sheet the manager maintains remotely,
/// for syncing into the app's local preset products.
///
/// Expected sheet layout (first row may optionally be a header row, which
/// is automatically skipped if its price column isn't a valid number):
///   Column A: Product Name
///   Column B: Unit Price
class GoogleSheetsService {
  GoogleSheetsService._internal();

  static final GoogleSheetsService instance = GoogleSheetsService._internal();

  /// Extracts the Sheet ID from either a raw ID or a full Google Sheets
  /// URL, so the manager can paste either format into the app.
  String? extractSheetId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final urlPattern = RegExp(r'/spreadsheets/d/([a-zA-Z0-9-_]+)');
    final match = urlPattern.firstMatch(trimmed);
    if (match != null) {
      return match.group(1);
    }

    // Assume the input is already a raw Sheet ID if it doesn't match a URL.
    if (!trimmed.contains('/') && !trimmed.contains(' ')) {
      return trimmed;
    }

    return null;
  }

  Future<SheetsOperationResult> fetchProducts({
    required String sheetIdOrUrl,
    String range = 'A:B',
  }) async {
    final sheetId = extractSheetId(sheetIdOrUrl);
    if (sheetId == null) {
      return SheetsOperationResult.fail(
        'Could not read a valid Sheet ID or URL.',
      );
    }

    if (!GoogleDriveService.instance.isSignedIn) {
      return SheetsOperationResult.fail(
        'Not signed in to Google. Connect a Google account first.',
      );
    }

    try {
      final client = await _getAuthenticatedClient();
      if (client == null) {
        return SheetsOperationResult.fail(
          'Could not authenticate with Google. Try signing in again.',
        );
      }

      final sheetsApi = sheets.SheetsApi(client);
      final valueRange = await sheetsApi.spreadsheets.values.get(
        sheetId,
        range,
      );
      client.close();

      final rows = valueRange.values;
      if (rows == null || rows.isEmpty) {
        return SheetsOperationResult.fail(
          'The sheet appears to be empty or the range is incorrect.',
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
          // Skips header rows (e.g. "Product Name" / "Unit Price") or any
          // malformed row automatically, without failing the whole sync.
          continue;
        }

        products.add(SheetProductRow(name: name, price: price));
      }

      if (products.isEmpty) {
        return SheetsOperationResult.fail(
          'No valid product rows found in the sheet.',
        );
      }

      return SheetsOperationResult.ok(
        products,
        '${products.length} product(s) read from sheet.',
      );
    } catch (e) {
      return SheetsOperationResult.fail('Sheet read failed: $e');
    }
  }

  Future<http.Client?> _getAuthenticatedClient() async {
    final account = GoogleDriveService.instance.currentAccountForAuth;
    if (account == null) return null;
    try {
      final authHeaders = await account.authHeaders;
      return _SheetsAuthClient(authHeaders);
    } catch (_) {
      return null;
    }
  }
}

class _SheetsAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _SheetsAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}