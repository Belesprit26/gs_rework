import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../domain/geyser/entities/geyser_config.dart';

/// Reads and writes per-device geyser configuration from Firestore.
///
/// All fields live in a single document at
/// `users/{uid}/geyser_config/{deviceId}`.
///
/// On first access, if the document is missing or incomplete, legacy
/// fields are migrated from the user-level document (`users/{uid}`).
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

  /// Streams the [GeyserConfig] for [deviceId].
  ///
  /// Handles three migration scenarios transparently:
  /// 1. No device doc → full migrate from user doc
  /// 2. Device doc exists but is missing `costPerKwh` → backfill from user doc
  /// 3. Device doc has all fields → direct read (fast path)
  Stream<GeyserConfig> watchConfig(String deviceId) {
    return _deviceDoc(deviceId).snapshots().asyncMap((snap) async {
      if (!snap.exists) {
        return _migrateFullConfig(deviceId);
      }
      final data = snap.data()!;
      if (!data.containsKey('costPerKwh')) {
        return _backfillUserFields(deviceId, data);
      }
      return GeyserConfig.fromMap(data);
    });
  }

  /// Saves all config fields to the device document.
  Future<void> saveConfig(String deviceId, GeyserConfig config) async {
    await _deviceDoc(deviceId).set(config.toMap(), SetOptions(merge: true));
  }

  /// First-time migration: copy all four fields from the legacy user
  /// doc into the per-device subcollection.
  Future<GeyserConfig> _migrateFullConfig(String deviceId) async {
    final userSnap = await _userDoc().get();
    final config = GeyserConfig.fromMap(userSnap.data());
    await _deviceDoc(deviceId).set(config.toMap());
    return config;
  }

  /// Backfill for users whose device doc was created before costPerKwh
  /// and householdSize were moved to per-device storage.  Reads the
  /// missing fields from the user doc and patches the device doc.
  Future<GeyserConfig> _backfillUserFields(
    String deviceId,
    Map<String, dynamic> deviceData,
  ) async {
    final userSnap = await _userDoc().get();
    final userMap = userSnap.data() ?? {};
    final config = GeyserConfig(
      tankSize: (deviceData['tankSize'] as num?)?.toInt() ?? 150,
      elementKw: (deviceData['elementKw'] as num?)?.toDouble() ?? 3.0,
      costPerKwh: (userMap['costPerKwh'] as num?)?.toDouble() ?? 2.79,
      householdSize: (userMap['householdSize'] as num?)?.toInt() ?? 2,
    );
    await _deviceDoc(deviceId).set(config.toMap(), SetOptions(merge: true));
    return config;
  }
}
