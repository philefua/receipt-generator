import 'dart:convert';
import 'dart:typed_data';
import 'package:base32/base32.dart';
import 'package:cryptography/cryptography.dart';
import 'package:hive/hive.dart';
import '../models/license_state.dart';
import 'device_id_service.dart';
import 'device_registry_service.dart';

enum PlanTier { oneMonth, threeMonths, sixMonths, oneYear, lifetime }

extension PlanTierDuration on PlanTier {
  int get durationDays {
    switch (this) {
      case PlanTier.oneMonth:
        return 31;
      case PlanTier.threeMonths:
        return 93;
      case PlanTier.sixMonths:
        return 186;
      case PlanTier.oneYear:
        return 372;
      case PlanTier.lifetime:
        return 0;
    }
  }
}

enum ActivationCodeError { badFormat, badSignature, deviceMismatch, alreadyRedeemed }

class ActivationCodeResult {
  final bool isValid;
  final PlanTier? planTier;
  final DateTime? issuedAt;
  final ActivationCodeError? error;

  const ActivationCodeResult._valid(this.planTier, this.issuedAt)
      : isValid = true,
        error = null;

  const ActivationCodeResult._invalid(this.error)
      : isValid = false,
        planTier = null,
        issuedAt = null;

  factory ActivationCodeResult.valid(PlanTier tier, DateTime issuedAt) =>
      ActivationCodeResult._valid(tier, issuedAt);

  factory ActivationCodeResult.invalid(ActivationCodeError error) =>
      ActivationCodeResult._invalid(error);
}

/// Bundled snapshot of this device's current license state, for display
/// purposes (Manager Backend status card).
class LicenseStatusSummary {
  final String deviceId;
  final bool isLifetime;
  final DateTime? effectiveExpiry;
  final int daysRemaining;

  /// 'trial', 'subscription', or 'lifetime'.
  final String planLabel;

  const LicenseStatusSummary({
    required this.deviceId,
    required this.isLifetime,
    required this.effectiveExpiry,
    required this.daysRemaining,
    required this.planLabel,
  });
}

class LicenseService {
  LicenseService._();
  static final LicenseService instance = LicenseService._();

  static const _boxName = 'license_state';
  static const _trialDurationDays = 28;

  static const _publicKeyBase64 = 'DmiBGrhOrxK2lfyFQBJdLJglW3OQ12UHC4Rv/E4bvEM=';

  static final DateTime _payloadEpoch = DateTime.utc(2020, 1, 1);

  Box<LicenseState>? _box;

  Future<Box<LicenseState>> get _licenseBox async {
    _box ??= await Hive.openBox<LicenseState>(_boxName);
    return _box!;
  }

  Future<LicenseState> _state() async {
    final box = await _licenseBox;
    if (box.isEmpty) {
      final fresh = LicenseState();
      await box.add(fresh);
      return fresh;
    }
    return box.getAt(0)!;
  }

  Future<DateTime> protectedNow() async {
    final state = await _state();
    final systemNow = DateTime.now().toUtc();

    final storedMillis = state.highWaterMarkUtcMillis;
    final highWaterMark = storedMillis != null
        ? DateTime.fromMillisecondsSinceEpoch(storedMillis, isUtc: true)
        : systemNow;

    final effectiveNow = systemNow.isAfter(highWaterMark) ? systemNow : highWaterMark;

    if (storedMillis == null || effectiveNow.isAfter(highWaterMark)) {
      state.highWaterMarkUtcMillis = effectiveNow.millisecondsSinceEpoch;
      await state.save();
    }

    return effectiveNow;
  }

  Future<void> _ensureInstallAnchor() async {
    final state = await _state();
    if (state.installTimestampUtcMillis != null) return;

    final now = await protectedNow();
    state.installTimestampUtcMillis = now.millisecondsSinceEpoch;
    state.trialEndUtcMillis =
        now.add(const Duration(days: _trialDurationDays)).millisecondsSinceEpoch;
    await state.save();
  }

  Future<DateTime> trialEndDate() async {
    await _ensureInstallAnchor();
    final state = await _state();
    return DateTime.fromMillisecondsSinceEpoch(
      state.trialEndUtcMillis!,
      isUtc: true,
    );
  }

  Future<bool> isTrialActive() async {
    final now = await protectedNow();
    final end = await trialEndDate();
    return now.isBefore(end);
  }

  Future<int> trialDaysRemaining() async {
    final now = await protectedNow();
    final end = await trialEndDate();
    if (now.isAfter(end)) return 0;
    return end.difference(now).inDays;
  }

  Uint8List _hexToBytes(String hex) {
    final clean = hex.trim();
    final bytes = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  String _normalizeCode(String rawCode) {
    return rawCode.replaceAll('-', '').replaceAll(RegExp(r'\s'), '').toUpperCase();
  }

  Future<ActivationCodeResult> verifyActivationCode(String rawCode) async {
    final cleaned = _normalizeCode(rawCode);

    Uint8List allBytes;
    try {
      allBytes = Uint8List.fromList(base32.decode(cleaned));
    } catch (_) {
      return ActivationCodeResult.invalid(ActivationCodeError.badFormat);
    }

    if (allBytes.length != 75) {
      return ActivationCodeResult.invalid(ActivationCodeError.badFormat);
    }

    final payloadBytes = allBytes.sublist(0, 11);
    final signatureBytes = allBytes.sublist(11, 75);

    final algorithm = Ed25519();
    final publicKey = SimplePublicKey(
      base64Decode(_publicKeyBase64),
      type: KeyPairType.ed25519,
    );

    final signatureIsValid = await algorithm.verify(
      payloadBytes,
      signature: Signature(signatureBytes, publicKey: publicKey),
    );

    if (!signatureIsValid) {
      return ActivationCodeResult.invalid(ActivationCodeError.badSignature);
    }

    final codeDeviceIdBytes = payloadBytes.sublist(0, 8);
    final planTierByte = payloadBytes[8];
    final issuedAtDays = (payloadBytes[9] << 8) | payloadBytes[10];

    if (planTierByte >= PlanTier.values.length) {
      return ActivationCodeResult.invalid(ActivationCodeError.badFormat);
    }

    final thisDeviceIdHex = await DeviceIdService.instance.getDeviceId();
    final thisDeviceIdBytes = _hexToBytes(thisDeviceIdHex);

    if (!_bytesEqual(codeDeviceIdBytes, thisDeviceIdBytes)) {
      return ActivationCodeResult.invalid(ActivationCodeError.deviceMismatch);
    }

    final planTier = PlanTier.values[planTierByte];
    final issuedAt = _payloadEpoch.add(Duration(days: issuedAtDays));

    return ActivationCodeResult.valid(planTier, issuedAt);
  }

  Future<DateTime?> _currentEffectiveExpiry() async {
    final state = await _state();
    if (state.subscriptionEndUtcMillis != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        state.subscriptionEndUtcMillis!,
        isUtc: true,
      );
    }
    return trialEndDate();
  }

  Future<bool> isLicensedActive() async {
    final state = await _state();
    if (state.isLifetime) return true;

    final now = await protectedNow();
    final expiry = await _currentEffectiveExpiry();
    return expiry != null && now.isBefore(expiry);
  }

  Future<void> _applyActivationCode(
    ActivationCodeResult result,
    String normalizedCode,
  ) async {
    final state = await _state();
    final tier = result.planTier!;
    final now = await protectedNow();

    if (tier == PlanTier.lifetime) {
      state.isLifetime = true;
      state.activationHistory = [...state.activationHistory, normalizedCode];
      await state.save();
      return;
    }

    final currentExpiry = await _currentEffectiveExpiry();
    final baseTime = (currentExpiry != null && currentExpiry.isAfter(now))
        ? currentExpiry
        : now;

    final newExpiry = baseTime.add(Duration(days: tier.durationDays));

    state.subscriptionEndUtcMillis = newExpiry.millisecondsSinceEpoch;
    state.activationHistory = [...state.activationHistory, normalizedCode];
    await state.save();
  }

  Future<ActivationCodeResult> redeemActivationCode(String rawCode) async {
    final result = await verifyActivationCode(rawCode);
    if (!result.isValid) return result;

    final normalized = _normalizeCode(rawCode);
    final state = await _state();

    if (state.activationHistory.contains(normalized)) {
      return ActivationCodeResult.invalid(ActivationCodeError.alreadyRedeemed);
    }

    await _applyActivationCode(result, normalized);
    return result;
  }

  Future<String> _currentPlanTierLabel() async {
    final state = await _state();
    if (state.isLifetime) return 'lifetime';
    if (state.subscriptionEndUtcMillis != null) return 'subscription';
    return 'trial';
  }

  Future<void> ensureDeviceRegistered({
    required String businessName,
    required String whatsappNumber,
  }) async {
    await _ensureInstallAnchor();

    final state = await _state();
    final now = await protectedNow();

    final lastCheckInMillis = state.lastRegistryCheckInUtcMillis;
    final dueForCheckIn = !state.hasSucceededRegistryCheck ||
        lastCheckInMillis == null ||
        now
                .difference(DateTime.fromMillisecondsSinceEpoch(
                    lastCheckInMillis,
                    isUtc: true))
                .inHours >=
            24;

    if (!dueForCheckIn) return;

    try {
      final deviceId = await DeviceIdService.instance.getDeviceId();
      final planTier = await _currentPlanTierLabel();

      final result = await DeviceRegistryService.instance.registerOrCheckIn(
        deviceId: deviceId,
        businessName: businessName,
        whatsappNumber: whatsappNumber,
        planTier: planTier,
      );

      if (!result.success) return;

      if (!state.hasSucceededRegistryCheck) {
        final registryTrialEnd = result.firstRegisteredDate!
            .add(const Duration(days: _trialDurationDays));
        final localTrialEnd = state.trialEndUtcMillis != null
            ? DateTime.fromMillisecondsSinceEpoch(
                state.trialEndUtcMillis!,
                isUtc: true,
              )
            : null;

        if (localTrialEnd == null || registryTrialEnd.isBefore(localTrialEnd)) {
          state.installTimestampUtcMillis =
              result.firstRegisteredDate!.millisecondsSinceEpoch;
          state.trialEndUtcMillis = registryTrialEnd.millisecondsSinceEpoch;
        }

        state.hasSucceededRegistryCheck = true;
      }

      state.lastRegistryCheckInUtcMillis = now.millisecondsSinceEpoch;
      await state.save();
    } catch (_) {
      // Silent failure is intentional — background, non-blocking, and
      // retried automatically on the next launch.
    }
  }

  /// Bundles device ID, plan label, and remaining days into one snapshot
  /// for display — used by the Manager Backend's license status card.
  Future<LicenseStatusSummary> getStatusSummary() async {
    final deviceId = await DeviceIdService.instance.getDeviceId();
    final state = await _state();
    final now = await protectedNow();

    if (state.isLifetime) {
      return LicenseStatusSummary(
        deviceId: deviceId,
        isLifetime: true,
        effectiveExpiry: null,
        daysRemaining: 0,
        planLabel: 'lifetime',
      );
    }

    final expiry = await _currentEffectiveExpiry();
    final daysRemaining =
        (expiry != null && expiry.isAfter(now)) ? expiry.difference(now).inDays : 0;
    final planLabel = state.subscriptionEndUtcMillis != null ? 'subscription' : 'trial';

    return LicenseStatusSummary(
      deviceId: deviceId,
      isLifetime: false,
      effectiveExpiry: expiry,
      daysRemaining: daysRemaining,
      planLabel: planLabel,
    );
  }
}