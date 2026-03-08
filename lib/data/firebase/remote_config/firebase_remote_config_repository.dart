import 'package:firebase_remote_config/firebase_remote_config.dart';

import '../../../domain/remote_config/repositories/remote_config_repository.dart';

class FirebaseRemoteConfigRepository implements RemoteConfigRepository {
  FirebaseRemoteConfigRepository({
    required FirebaseRemoteConfig remoteConfig,
  }) : _rc = remoteConfig;

  final FirebaseRemoteConfig _rc;

  static const _keyMaintenance = 'maintenance_mode';
  static const _keyMinVersion = 'min_supported_version';

  @override
  Future<void> initialize() async {
    // Set defaults so the gate always has a value, even offline.
    await _rc.setDefaults(const <String, dynamic>{
      _keyMaintenance: false,
      _keyMinVersion: '1.0.0',
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
}
