// lib/services/device_id_service.dart
import 'package:flutter/services.dart';

/// Reads the device's hardware-level ANDROID_ID via a native platform
/// channel. Used to bind license activation to a specific device —
/// survives uninstall/reinstall and Google account switches, unlike
/// anything stored in Hive or tied to a signed-in account.
class DeviceIdService {
  DeviceIdService._();
  static final DeviceIdService instance = DeviceIdService._();

  static const _channel = MethodChannel('com.example.receipt_generator/device_id');

  String? _cachedDeviceId;

  /// Returns the device's ANDROID_ID as a hex string. Cached after the
  /// first successful read for the lifetime of the app process.
  Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      final String? id = await _channel.invokeMethod<String>('getDeviceId');
      if (id == null || id.isEmpty) {
        throw PlatformException(
          code: 'EMPTY_DEVICE_ID',
          message: 'ANDROID_ID returned null or empty',
        );
      }
      _cachedDeviceId = id;
      return id;
    } on PlatformException catch (e) {
      // This should be rare on real Android hardware, but surface it
      // clearly rather than silently — a null device ID must never
      // silently pass license checks.
      throw Exception('Failed to read device ID: ${e.message}');
    }
  }
}