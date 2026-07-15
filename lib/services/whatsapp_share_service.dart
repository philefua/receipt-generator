import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result wrapper for share operations so calling UI code can display a
/// clean success/failure message without needing try/catch everywhere.
class ShareOperationResult {
  final bool success;
  final String message;

  const ShareOperationResult({required this.success, required this.message});

  factory ShareOperationResult.ok([String message = 'Shared successfully.']) =>
      ShareOperationResult(success: true, message: message);

  factory ShareOperationResult.fail(String message) =>
      ShareOperationResult(success: false, message: message);
}

/// Captures a visually composed receipt (via RepaintBoundary), saves it to
/// the device cache directory, and shares it toward WhatsApp.
class WhatsappShareService {
  WhatsappShareService._internal();

  static final WhatsappShareService instance =
      WhatsappShareService._internal();

  Future<Uint8List> captureReceiptAsImage(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) async {
    final RenderObject? renderObject =
        boundaryKey.currentContext?.findRenderObject();

    if (renderObject == null || renderObject is! RenderRepaintBoundary) {
      throw StateError(
        'No RepaintBoundary found for the given key. Ensure the receipt '
        'widget is wrapped in a RepaintBoundary and has been rendered '
        'at least one frame before capturing.',
      );
    }

    final RenderRepaintBoundary boundary = renderObject;

    if (boundary.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return captureReceiptAsImage(boundaryKey, pixelRatio: pixelRatio);
    }

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    if (byteData == null) {
      throw StateError('Failed to encode captured image to PNG bytes.');
    }

    return byteData.buffer.asUint8List();
  }

  Future<File> saveImageToTempFile(
    Uint8List imageBytes, {
    required String fileNamePrefix,
  }) async {
    final Directory cacheDir = await getTemporaryDirectory();
    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String filePath =
        '${cacheDir.path}/${fileNamePrefix}_$timestamp.png';

    final File file = File(filePath);
    await file.writeAsBytes(imageBytes, flush: true);
    return file;
  }

  Future<void> clearCachedReceiptImages({
    String fileNamePrefix = 'receipt',
  }) async {
    try {
      final Directory cacheDir = await getTemporaryDirectory();
      final List<FileSystemEntity> entities = cacheDir.listSync();
      for (final entity in entities) {
        if (entity is File &&
            entity.path.contains(fileNamePrefix) &&
            entity.path.endsWith('.png')) {
          await entity.delete();
        }
      }
    } catch (_) {
      // Non-critical cleanup failure; safe to ignore.
    }
  }

  /// Captures the receipt, saves it to cache, and opens the system share
  /// sheet with WhatsApp as one of the available targets.
  ///
  /// NOTE: On some Android devices (notably Samsung One UI), the share_plus
  /// plugin's internal result-tracking throws a LateInitializationError
  /// asynchronously, unrelated to whether the share sheet actually opened
  /// successfully. To avoid this ever surfacing as a false failure, the
  /// share call is deliberately NOT awaited here — it is fired and its
  /// error channel is separately caught and discarded, fully detached from
  /// this function's own success/failure return value.
  Future<ShareOperationResult> shareReceiptImage({
    required GlobalKey boundaryKey,
    String? receiptCode,
    String? captionPhoneNumber,
  }) async {
    final Uint8List bytes = await captureReceiptAsImage(boundaryKey);
    final File file = await saveImageToTempFile(
      bytes,
      fileNamePrefix: 'receipt_${receiptCode ?? 'export'}',
    );

    final String caption = captionPhoneNumber != null &&
            captionPhoneNumber.trim().isNotEmpty
        ? 'Receipt${receiptCode != null ? ' #$receiptCode' : ''} for $captionPhoneNumber'
        : 'Receipt${receiptCode != null ? ' #$receiptCode' : ''}';

    // Fire the share intent without awaiting its result. Attach a
    // catchError so any exception the plugin throws later is swallowed
    // silently rather than becoming an unhandled async error or being
    // mistakenly caught by an unrelated try/catch elsewhere.
    // ignore: unawaited_futures
    Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: caption,
    ).catchError((_) {
      return const ShareResult('', ShareResultStatus.success);
    });

    return ShareOperationResult.ok('Receipt shared successfully.');
  }

  /// Opens WhatsApp directly on the specified customer's chat thread with
  /// a pre-filled text message.
  Future<ShareOperationResult> openWhatsAppChat({
    required String phoneNumber,
    required String message,
  }) async {
    try {
      final String sanitized = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
      if (sanitized.isEmpty) {
        return ShareOperationResult.fail('Invalid WhatsApp phone number.');
      }

      final Uri uri = Uri.parse(
        'https://wa.me/$sanitized?text=${Uri.encodeComponent(message)}',
      );

      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      return launched
          ? ShareOperationResult.ok('WhatsApp chat opened.')
          : ShareOperationResult.fail(
              'Could not open WhatsApp. Is it installed?',
            );
    } catch (e) {
      return ShareOperationResult.fail('Failed to open WhatsApp chat: $e');
    }
  }

  /// Opens the specific customer's chat with a text message first, then
  /// immediately triggers the image share sheet.
  Future<ShareOperationResult> shareReceiptToCustomer({
    required GlobalKey boundaryKey,
    required String customerPhoneNumber,
    required String receiptCode,
    String greetingMessage =
        'Thank you for your purchase! Here is your receipt:',
  }) async {
    final chatResult = await openWhatsAppChat(
      phoneNumber: customerPhoneNumber,
      message: '$greetingMessage (Receipt #$receiptCode)',
    );

    if (!chatResult.success) {
      return chatResult;
    }

    await Future<void>.delayed(const Duration(milliseconds: 800));

    return shareReceiptImage(
      boundaryKey: boundaryKey,
      receiptCode: receiptCode,
      captionPhoneNumber: customerPhoneNumber,
    );
  }
}