import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result of a device registry check-in.
class DeviceRegistryResult {
  final bool success;
  final DateTime? firstRegisteredDate;
  final bool wasNewRegistration;
  final String? errorMessage;

  const DeviceRegistryResult._({
    required this.success,
    this.firstRegisteredDate,
    this.wasNewRegistration = false,
    this.errorMessage,
  });

  factory DeviceRegistryResult.ok({
    required DateTime firstRegisteredDate,
    required bool wasNewRegistration,
  }) =>
      DeviceRegistryResult._(
        success: true,
        firstRegisteredDate: firstRegisteredDate,
        wasNewRegistration: wasNewRegistration,
      );

  factory DeviceRegistryResult.fail(String message) =>
      DeviceRegistryResult._(success: false, errorMessage: message);
}

/// Talks to the Apps Script "Registered Devices" endpoint — a one-way
/// registration/check-in call, no Google sign-in required. Used both
/// for the one-time trial anti-reinstall check and, later, periodic
/// check-ins (Last Seen Date, current Plan Tier) on the same 24-hour
/// cadence as backup/sync.
class DeviceRegistryService {
  DeviceRegistryService._internal();

  static final DeviceRegistryService instance =
      DeviceRegistryService._internal();

  static const _endpointUrl =
      'https://script.google.com/macros/s/AKfycbzvZJAK7vy0TkxmF7EKn-GE3t5ttig4REwGy17fIrHijkOizAHrmf6j8aQPPVL7qBBSLQ/exec';

  static const _sharedSecret = 'eAj8h-rR9YvRTSm5couFlXTx3kLwxKwz9iyikdZQoXc';

  /// Registers a device if unseen, or checks in (updates Last Seen /
  /// Plan Tier) if already registered. Returns the *original*
  /// firstRegisteredDate either way — the caller uses this to anchor
  /// the trial, regardless of whether this was a new or existing row.
  ///
  /// businessName / whatsappNumber / country / planTier are all
  /// optional — pass whatever is currently known; the script only
  /// updates fields that are non-empty.
  Future<DeviceRegistryResult> registerOrCheckIn({
    required String deviceId,
    String? businessName,
    String? whatsappNumber,
    String? country,
    String? planTier,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(_endpointUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'secret': _sharedSecret,
              'deviceId': deviceId,
              'businessName': businessName ?? '',
              'whatsappNumber': whatsappNumber ?? '',
              'country': country ?? '',
              'planTier': planTier ?? '',
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return DeviceRegistryResult.fail(
          'Registry check failed (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      if (decoded['success'] != true) {
        return DeviceRegistryResult.fail(
          'Registry check failed: ${decoded['error'] ?? 'unknown error'}',
        );
      }

      final dateStr = decoded['firstRegisteredDate'] as String;
      final parts = dateStr.split('-').map(int.parse).toList();
      final firstRegisteredDate = DateTime.utc(parts[0], parts[1], parts[2]);

      return DeviceRegistryResult.ok(
        firstRegisteredDate: firstRegisteredDate,
        wasNewRegistration: decoded['wasNewRegistration'] == true,
      );
    } catch (e) {
      return DeviceRegistryResult.fail('Registry check failed: $e');
    }
  }
}