import 'package:hive/hive.dart';

part 'license_state.g.dart';

/// Holds all trial/license state for this device. Isolated from
/// BusinessSettings by design — this data is sensitive to correctness
/// (anti-rollback clock, activation history) and expected to grow
/// through the remaining build steps.
@HiveType(typeId: 4)
class LicenseState extends HiveObject {
  /// The latest time this device has ever observed, in UTC millis
  /// since epoch. Never goes backward — defeats simple clock rollback.
  @HiveField(0)
  int? highWaterMarkUtcMillis;

  /// When the app was first launched on this device, in UTC millis.
  /// Stamped once locally, then possibly overwritten by an earlier
  /// date from the device registry if this device was seen before.
  @HiveField(1)
  int? installTimestampUtcMillis;

  /// End of the 28-day trial window, in UTC millis.
  @HiveField(2)
  int? trialEndUtcMillis;

  /// End of the current subscription, in UTC millis. Null until the
  /// first paid activation code is ever redeemed on this device.
  @HiveField(3)
  int? subscriptionEndUtcMillis;

  /// True once a Lifetime code has been redeemed. Absorbing state.
  @HiveField(4)
  bool isLifetime = false;

  /// Append-only audit trail of applied activation codes.
  @HiveField(5)
  List<String> activationHistory = [];

  /// True once the device registry check has succeeded at least once.
  /// Before this, trial dates are trusted purely from local storage;
  /// the first success may retroactively correct them if this device
  /// was already registered under an earlier date (reinstall case).
  @HiveField(6)
  bool hasSucceededRegistryCheck = false;

  /// Last time a registry check-in succeeded, in UTC millis. Drives
  /// the 24-hour retry/check-in cadence, same rhythm as backup/sync.
  @HiveField(7)
  int? lastRegistryCheckInUtcMillis;
}