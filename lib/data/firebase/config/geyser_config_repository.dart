import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';

import '../../../domain/geyser/entities/device_config.dart';
import '../../../domain/geyser/entities/geyser_config.dart';
import '../../../domain/geyser/entities/user_config.dart';

/// Reads and writes geyser configuration from Firestore.
///
/// User-level fields (costPerKwh, householdSize) live on `users/{uid}`.
/// Device-level fields (tankSize, elementKw) live on
/// `users/{uid}/geyser_config/{deviceId}`.
///
/// On first access of a device config doc, if it doesn't exist, the
/// values are migrated from the user-level doc (backward compatibility).
class GeyserConfigRepository {
  GeyserConfigRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> _userDoc() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user');
    return _firestore.collection('users').doc(uid);
  }

  DocumentReference<Map<String, dynamic>> _deviceDoc(String deviceId) {
    return _userDoc().collection('geyser_config').doc(deviceId);
  }

  // ── User config (account-scoped) ─────────────────────────────────

  Stream<UserConfig> watchUserConfig() {
    return _userDoc().snapshots().map(
          (snap) => UserConfig.fromMap(snap.data()),
        );
  }

  Future<void> saveUserConfig(UserConfig config) async {
    await _userDoc().set(config.toMap(), SetOptions(merge: true));
  }

  // ── Device config (per-device) ───────────────────────────────────

  Stream<DeviceConfig> watchDeviceConfig(String deviceId) {
    return _deviceDoc(deviceId).snapshots().asyncMap((snap) async {
      if (snap.exists) {
        return DeviceConfig.fromMap(snap.data());
      }
      // First access — migrate from the user-level doc.
      return _migrateDeviceConfig(deviceId);
    });
  }

  Future<void> saveDeviceConfig(String deviceId, DeviceConfig config) async {
    await _deviceDoc(deviceId).set(config.toMap(), SetOptions(merge: true));
  }

  /// Copy device fields from the legacy user doc into the per-device
  /// subcollection.  Returns the migrated config.
  Future<DeviceConfig> _migrateDeviceConfig(String deviceId) async {
    final userSnap = await _userDoc().get();
    final legacy = GeyserConfig.fromMap(userSnap.data());
    final deviceConfig = legacy.deviceConfig;
    await _deviceDoc(deviceId).set(deviceConfig.toMap());
    return deviceConfig;
  }

  // ── Combined config stream (convenience) ─────────────────────────

  /// Streams a merged [GeyserConfig] from both sources.
  /// Emits whenever either source changes.
  Stream<GeyserConfig> watchConfig(String deviceId) {
    return Rx.combineLatest2<UserConfig, DeviceConfig, GeyserConfig>(
      watchUserConfig(),
      watchDeviceConfig(deviceId),
      (user, device) => GeyserConfig.fromParts(
        device: device,
        user: user,
      ),
    );
  }

  /// Legacy: read combined config from user doc only (pre-migration).
  Future<GeyserConfig> getConfig() async {
    final snap = await _userDoc().get();
    return GeyserConfig.fromMap(snap.data());
  }

  /// Legacy: save all config fields to user doc only.
  Future<void> saveConfig(GeyserConfig config) async {
    await _userDoc().set(config.toMap(), SetOptions(merge: true));
  }
}
