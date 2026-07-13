import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
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
///
/// IMPORTANT PLATFORM LIMITATION:
/// Neither Android nor WhatsApp expose an API that lets a third-party app
/// share an IMAGE directly into a specific contact's chat thread. That
/// targeting capability only exists for pre-filled TEXT messages via the
/// `wa.me` deep link scheme. This service therefore offers two flows:
///   1. [shareReceiptImage] — captures the receipt as a PNG and opens the
///      OS share sheet (WhatsApp will be one of the options; the user picks
///      the contact manually inside WhatsApp).
///   2. [openWhatsAppChat] — deep-links straight into a specific customer's
///      chat thread with a pre-filled text message (no image), using their
///      WhatsApp number.
/// For the closest possible experience to "one tap sends the image to that
/// customer", call [openWhatsAppChat] first (so the correct chat opens),
/// then call [shareReceiptImage] so the user can attach the image from the
/// share sheet or manually attach it inside the now-open chat.
class WhatsappShareService {
  WhatsappShareService._internal();

  static final WhatsappShareService instance =
      WhatsappShareService._internal();

  // ---------------------------------------------------------------------
  // Step 1: Capture the RepaintBoundary widget as PNG bytes
  // ---------------------------------------------------------------------

  /// Captures the widget attached to [boundaryKey] as PNG image bytes.
  /// [pixelRatio] controls output resolution; 3.0 gives crisp results on
  /// most phone screens without producing an oversized file.
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

  // ---------------------------------------------------------------------
  // Step 2: Persist the captured bytes to the device cache directory
  // ---------------------------------------------------------------------

  /// Saves [imageBytes] to a temporary file inside the app's cache
  /// directory and returns the resulting [File].
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

  /// Deletes previously generated temp receipt images from the cache
  /// directory. Safe to call periodically (e.g. on app start) to avoid
  /// cache bloat, since these files are meant to be short-lived.
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

  // ---------------------------------------------------------------------
  // Step 3a: Share the captured image via the OS share sheet
  // ---------------------------------------------------------------------

  /// Captures the receipt, saves it to cache, and opens the system share
  /// sheet with WhatsApp as one of the available targets. The customer's
  /// phone number cannot be pre-selected for image shares (OS limitation),
  /// so [captionPhoneNumber] is only used to enrich the share caption text
  /// as a helpful reminder to the cashier of who this is for.
  Future<ShareOperationResult> shareReceiptImage({
    required GlobalKey boundaryKey,
    String? receiptCode,
    String? captionPhoneNumber,
  }) async {
    try {
      final Uint8List bytes = await captureReceiptAsImage(boundaryKey);
      final File file = await saveImageToTempFile(
        bytes,
        fileNamePrefix: 'receipt_${receiptCode ?? 'export'}',
      );

      final String caption = captionPhoneNumber != null &&
              captionPhoneNumber.trim().isNotEmpty
          ? 'Receipt${receiptCode != null ? ' #$receiptCode' : ''} for $captionPhoneNumber'
          : 'Receipt${receiptCode != null ? ' #$receiptCode' : ''}';

      final ShareResult result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: caption,
        ),
      );

      if (result.status == ShareResultStatus.success) {
        return ShareOperationResult.ok('Receipt shared successfully.');
      } else if (result.status == ShareResultStatus.dismissed) {
        return ShareOperationResult.fail('Share sheet was dismissed.');
      }
      return ShareOperationResult.ok('Share sheet opened.');
    } catch (e) {
      return ShareOperationResult.fail('Failed to share receipt: $e');
    }
  }

  // ---------------------------------------------------------------------
  // Step 3b: Deep-link directly into a specific customer's WhatsApp chat
  // ---------------------------------------------------------------------

  /// Opens WhatsApp directly on the specified customer's chat thread with
  /// a pre-filled text message. This is the only mechanism WhatsApp exposes
  /// for targeting a specific contact programmatically — it works for text
  /// only, never for pre-attached media.
  ///
  /// [phoneNumber] should include the country code (digits only, no '+' or
  /// spaces required — this method sanitizes it automatically).
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

  // ---------------------------------------------------------------------
  // Convenience: combined flow used by the checkout screen
  // ---------------------------------------------------------------------

  /// Opens the specific customer's chat with a text message first (so the
  /// correct thread is active), then immediately triggers the image share
  /// sheet so the cashier can attach the receipt with minimal friction.
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