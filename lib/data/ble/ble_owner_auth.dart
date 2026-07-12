import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/ble/gatt_uuids.dart';
import '../../core/ble/owner_auth_codec.dart';
import '../../core/debug/debug_log.dart';
import '../../domain/ble/repositories/ble_repository.dart';
import '../local/prefs_manager.dart';

/// Outcome of an owner-unlock attempt.
enum OwnerUnlockResult {
  /// Challenge answered correctly — this connection may write.
  unlocked,

  /// Device has no owner-auth characteristic (pre-lock firmware) —
  /// nothing to unlock.
  notRequired,

  /// We hold no key for this device (not signed into the owning
  /// account, or the device was never keyed).
  noKey,

  /// The device rejected our response — wrong key for this device.
  locked,
}

/// Unlocks the BLE owner-lock (firmware `owner_auth.c`).
///
/// The 32-byte device key is created at provisioning and lives in the
/// owning account's Firestore scope (`users/{uid}/geyser_config/{did}`,
/// field `bleOwnerKey`). Any phone signed into the household account
/// fetches it once, caches it in prefs, and can then unlock offline.
class BleOwnerAuth {
  BleOwnerAuth({
    required BleRepository bleRepository,
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
    required PrefsManager prefsManager,
  })  : _ble = bleRepository,
        _auth = auth,
        _firestore = firestore,
        _prefs = prefsManager;

  final BleRepository _ble;
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final PrefsManager _prefs;

  /// Run the challenge-response unlock on the current connection.
  Future<OwnerUnlockResult> unlock(String rtdbDeviceId) async {
    // 1. Challenge. Older firmware has no 0x0E → nothing to unlock.
    Uint8List nonce;
    try {
      nonce = await _ble.readCharacteristic(GattUuids.ownerAuth.str);
    } catch (_) {
      return OwnerUnlockResult.notRequired;
    }
    if (nonce.isEmpty) return OwnerUnlockResult.notRequired;

    // 2. Key — prefs cache, else the account's Firestore scope.
    final key = await _obtainKey(rtdbDeviceId);
    if (key == null) {
      debugLog('OwnerAuth', 'No key for $rtdbDeviceId (cache + cloud)');
      return OwnerUnlockResult.noKey;
    }

    // 3. Response. The firmware rejects a wrong HMAC with an ATT
    //    authorization error, which surfaces here as a write failure.
    try {
      await _ble.writeCharacteristic(
        GattUuids.ownerAuth.str,
        computeUnlockResponse(key: key, nonce: nonce),
      );
      debugLog('OwnerAuth', 'Unlocked $rtdbDeviceId');
      return OwnerUnlockResult.unlocked;
    } catch (e) {
      debugLog('OwnerAuth', 'Unlock rejected for $rtdbDeviceId: $e');
      return OwnerUnlockResult.locked;
    }
  }

  /// Persist a key locally + to the owning account's Firestore scope.
  Future<void> storeKey({
    required String rtdbDeviceId,
    required Uint8List key,
  }) async {
    final b64 = base64Encode(key);
    await _prefs.setBleOwnerKey(rtdbDeviceId, b64);

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _firestore
          .doc('users/$uid/geyser_config/$rtdbDeviceId')
          .set({'bleOwnerKey': b64}, SetOptions(merge: true));
    } catch (e) {
      // Local cache still works for this phone; other phones will
      // pick the key up once a later store/rotation succeeds.
      debugLog('OwnerAuth', 'Cloud key store failed: $e');
    }
  }

  /// Generate + install a new key on the connected device (requires an
  /// owner-unlocked connection), then persist it. Old cached keys on
  /// other phones stop working — that's the revocation mechanism.
  Future<bool> rotateKey(String rtdbDeviceId) async {
    final newKey = generateOwnerKey();
    try {
      await _ble.writeCharacteristic(GattUuids.provOwnerKey.str, newKey);
    } catch (e) {
      debugLog('OwnerAuth', 'Key rotation write failed: $e');
      return false;
    }
    await storeKey(rtdbDeviceId: rtdbDeviceId, key: newKey);
    debugLog('OwnerAuth', 'Key rotated for $rtdbDeviceId');
    return true;
  }

  // ── Private ───────────────────────────────────────────────────────

  Future<Uint8List?> _obtainKey(String rtdbDeviceId) async {
    final cached = _prefs.getBleOwnerKey(rtdbDeviceId);
    if (cached != null && cached.isNotEmpty) {
      return Uint8List.fromList(base64Decode(cached));
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;

    try {
      final snap = await _firestore
          .doc('users/$uid/geyser_config/$rtdbDeviceId')
          .get();
      final b64 = snap.data()?['bleOwnerKey'] as String?;
      if (b64 == null || b64.isEmpty) return null;

      await _prefs.setBleOwnerKey(rtdbDeviceId, b64);
      debugLog('OwnerAuth', 'Key fetched from cloud for $rtdbDeviceId');
      return Uint8List.fromList(base64Decode(b64));
    } catch (e) {
      debugLog('OwnerAuth', 'Cloud key fetch failed: $e');
      return null;
    }
  }
}
