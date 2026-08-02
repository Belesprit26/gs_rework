import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../../../domain/remote_config/repositories/remote_config_repository.dart';

class FirebaseRemoteConfigRepository implements RemoteConfigRepository {
  FirebaseRemoteConfigRepository({
    required FirebaseRemoteConfig remoteConfig,
  }) : _rc = remoteConfig;

  final FirebaseRemoteConfig _rc;

  static const _keyMaintenance = 'maintenance_mode';
  static const _keyMinVersion = 'min_supported_version';

  /// Standing loss per tank size, kWh/24 h. Defaults are typical values
  /// for SANS 151 tanks; older or poorly-lagged geysers run higher.
  /// Recalibrate from metered installs by overriding these in the
  /// Remote Config console — no app release needed.
  static const _keyStandingLoss100 = 'standing_loss_kwh_100l';
  static const _keyStandingLoss150 = 'standing_loss_kwh_150l';
  static const _keyStandingLoss200 = 'standing_loss_kwh_200l';

  @override
  Future<void> initialize() async {
    // Set defaults so the gate always has a value, even offline.
    await _rc.setDefaults(const <String, dynamic>{
      _keyMaintenance: false,
      _keyMinVersion: '1.0.0',
      _keyStandingLoss100: 1.6,
      _keyStandingLoss150: 2.2,
      _keyStandingLoss200: 2.8,
    });

    await _rc.setConfigSettings(RemoteConfigSettings(
      fetchTimeout: const Duration(seconds: 10),
      minimumFetchInterval: const Duration(minutes: 5),
    ));

    try {
      await _rc.fetchAndActivate();
    } catch (_) {
      // Silently degrade — defaults will be used.
    }
  }

  @override
  bool get isMaintenanceMode => _rc.getBool(_keyMaintenance);

  @override
  String get minSupportedVersion => _rc.getString(_keyMinVersion);

  @override
  double standingLossKwhPerDay(int tankSizeLitres) {
    final key = switch (tankSizeLitres) {
      <= 100 => _keyStandingLoss100,
      <= 150 => _keyStandingLoss150,
      _ => _keyStandingLoss200,
    };
    final value = _rc.getDouble(key);
    // getDouble returns 0.0 for an unset/!unparseable key; fall back to
    // the 150 L default rather than reporting an impossible zero saving.
    return value > 0 ? value : 2.2;
  }
}
