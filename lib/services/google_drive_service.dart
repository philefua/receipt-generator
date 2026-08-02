import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

/// Result wrapper for Google Drive operations.
class DriveOperationResult {
  final bool success;
  final String message;

  const DriveOperationResult({required this.success, required this.message});

  factory DriveOperationResult.ok([String message = 'OK']) =>
      DriveOperationResult(success: true, message: message);

  factory DriveOperationResult.fail(String message) =>
      DriveOperationResult(success: false, message: message);
}

/// Result of creating or reading back the product Sheet.
class ProductSheetResult {
  final bool success;
  final String message;
  final String? fileId;
  final String? csvContent;

  const ProductSheetResult({
    required this.success,
    required this.message,
    this.fileId,
    this.csvContent,
  });

  factory ProductSheetResult.ok({
    String message = 'OK',
    String? fileId,
    String? csvContent,
  }) =>
      ProductSheetResult(
        success: true,
        message: message,
        fileId: fileId,
        csvContent: csvContent,
      );

  factory ProductSheetResult.fail(String message) =>
      ProductSheetResult(success: false, message: message);
}

/// A minimal http.Client that attaches the signed-in Google account's
/// OAuth access token to every outgoing request, bridging google_sign_in
/// (which handles the actual sign-in UI/consent flow) to the googleapis
/// package (which expects a standard authenticated http.Client).
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}

/// Handles Google sign-in, uploading the receipt history Excel export,
/// and creating/reading the manager's product-list Google Sheet — all
/// exclusively through the Drive API under the single drive.file scope.
/// The product Sheet is created by this app (via CSV-to-Sheets import),
/// so drive.file's "files the app itself creates" boundary covers both
/// writing it initially and reading it back later; no Sheets API scope
/// is used anywhere in this app.
class GoogleDriveService {
  GoogleDriveService._internal();

  static final GoogleDriveService instance = GoogleDriveService._internal();

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive.file',
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: _scopes);

  GoogleSignInAccount? _currentAccount;

  bool get isSignedIn => _currentAccount != null;

  String? get signedInEmail => _currentAccount?.email;
  GoogleSignInAccount? get currentAccountForAuth => _currentAccount;

  /// Attempts a silent sign-in first (for a previously-connected account),
  /// falling back to nothing if none exists — used on app startup to
  /// restore a prior connection without prompting the manager again.
  Future<bool> trySilentSignIn() async {
    try {
      final account = await _googleSignIn.signInSilently();
      _currentAccount = account;
      return account != null;
    } catch (_) {
      _currentAccount = null;
      return false;
    }
  }

  /// Prompts the manager with Google's sign-in UI. Only accounts listed
  /// as test users on the OAuth consent screen will succeed while the
  /// app remains in Testing publishing status.
  Future<DriveOperationResult> signIn() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return DriveOperationResult.fail('Sign-in was cancelled.');
      }
      _currentAccount = account;
      return DriveOperationResult.ok('Signed in as ${account.email}');
    } catch (e) {
      return DriveOperationResult.fail('Sign-in failed: $e');
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentAccount = null;
  }

  /// Builds an authenticated http.Client using the current sign-in's
  /// OAuth headers, required by every googleapis call below.
  Future<http.Client?> _getAuthenticatedClient() async {
    if (_currentAccount == null) return null;
    try {
      final authHeaders = await _currentAccount!.authHeaders;
      return _GoogleAuthClient(authHeaders);
    } catch (_) {
      return null;
    }
  }

  /// Uploads [bytes] (an Excel .xlsx file) to the signed-in account's
  /// Google Drive under [fileName]. Creates a new file each call — Drive
  /// allows duplicate file names, so retention/cleanup of older backups
  /// is handled separately if desired.
  Future<DriveOperationResult> uploadExcelBackup({
    required Uint8List bytes,
    required String fileName,
  }) async {
    if (!isSignedIn) {
      return DriveOperationResult.fail(
        'Not signed in to Google. Connect a Google account first.',
      );
    }

    try {
      final client = await _getAuthenticatedClient();
      if (client == null) {
        return DriveOperationResult.fail(
          'Could not authenticate with Google. Try signing in again.',
        );
      }

      final driveApi = drive.DriveApi(client);

      final driveFile = drive.File()
        ..name = fileName
        ..mimeType =
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

      final media = drive.Media(
        Stream.value(bytes),
        bytes.length,
        contentType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );

      await driveApi.files.create(driveFile, uploadMedia: media);
      client.close();

      return DriveOperationResult.ok('Backup uploaded to Google Drive.');
    } catch (e) {
      return DriveOperationResult.fail('Drive upload failed: $e');
    }
  }

  /// Creates a new native Google Sheet in the manager's Drive, pre-filled
  /// with a header row and example rows, by uploading CSV content and
  /// letting Drive auto-convert it into Sheets format. This is the only
  /// way this app ever writes a Sheet, and it happens entirely through
  /// the Drive API — no Sheets API scope is used. Because the app itself
  /// creates this file, drive.file continues to grant access to it for
  /// as long as the manager keeps using this app.
  Future<ProductSheetResult> createProductSheet() async {
    if (!isSignedIn) {
      return ProductSheetResult.fail(
        'Not signed in to Google. Connect a Google account first.',
      );
    }

    try {
      final client = await _getAuthenticatedClient();
      if (client == null) {
        return ProductSheetResult.fail(
          'Could not authenticate with Google. Try signing in again.',
        );
      }

      final driveApi = drive.DriveApi(client);

      const csvTemplate = 'Product Name,Price\n'
          'Custom T-Shirt Print,3500\n'
          'Vinyl Banner (per sqm),2500\n'
          'Business Card (100 pcs),5000\n';

      final csvBytes = utf8.encode(csvTemplate);

      final driveFile = drive.File()
        ..name = 'Receipt Generator - Product List'
        ..mimeType = 'application/vnd.google-apps.spreadsheet';

      final media = drive.Media(
        Stream.value(csvBytes),
        csvBytes.length,
        contentType: 'text/csv',
      );

      final created = await driveApi.files.create(
        driveFile,
        uploadMedia: media,
        $fields: 'id',
      );
      client.close();

      if (created.id == null) {
        return ProductSheetResult.fail(
          'Sheet was created but no file ID was returned.',
        );
      }

      return ProductSheetResult.ok(
        message: 'Product Sheet created.',
        fileId: created.id,
      );
    } catch (e) {
      return ProductSheetResult.fail('Could not create product Sheet: $e');
    }
  }

  /// Reads back the manager's product Sheet as CSV text, via Drive's
  /// export endpoint — again, entirely through the Drive API, not the
  /// Sheets API. Only works for a file this app created (or otherwise
  /// has drive.file access to).
  Future<ProductSheetResult> exportProductSheetAsCsv(String fileId) async {
    if (!isSignedIn) {
      return ProductSheetResult.fail(
        'Not signed in to Google. Connect a Google account first.',
      );
    }

    try {
      final client = await _getAuthenticatedClient();
      if (client == null) {
        return ProductSheetResult.fail(
          'Could not authenticate with Google. Try signing in again.',
        );
      }

      final driveApi = drive.DriveApi(client);

      final media = await driveApi.files.export(
        fileId,
        'text/csv',
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final bytes = <int>[];
      await for (final chunk in media.stream) {
        bytes.addAll(chunk);
      }
      client.close();

      final csvContent = utf8.decode(bytes);

      return ProductSheetResult.ok(
        message: 'Product Sheet read successfully.',
        fileId: fileId,
        csvContent: csvContent,
      );
    } catch (e) {
      return ProductSheetResult.fail('Could not read product Sheet: $e');
    }
  }
}