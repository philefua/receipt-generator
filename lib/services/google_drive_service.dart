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

/// Handles Google sign-in and uploading the receipt history Excel export
/// to the signed-in manager's Google Drive.
class GoogleDriveService {
  GoogleDriveService._internal();

  static final GoogleDriveService instance = GoogleDriveService._internal();

  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/spreadsheets',
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
}