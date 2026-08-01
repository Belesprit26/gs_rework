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
  ///
  /// A rejection with a cached key retries ONCE with a key re-fetched
  /// from Firestore: another household phone may have re-provisioned
  /// the device with a different key, and without this recovery the
  /// stale cache would lock this phone out permanently.
  Future<OwnerUnlockResult> unlock(String rtdbDeviceId) async {
    var result = await _attemptUnlock(rtdbDeviceId, forceCloudKey: false);
    if (result == OwnerUnlockResult.locked) {
      // Retry with a freshly fetched cloud key, but do NOT discard the
      // cached one first: a rejection can also come from a dropped link
      // mid-write, and if we are offline the cache is the only key we
      // have. _fetchCloudKey overwrites the cache itself on success.
      debugLog('OwnerAuth', 'Rejected — retrying with cloud key');
      result = await _attemptUnlock(rtdbDeviceId, forceCloudKey: true);
    }
    return result;
  }

  Future<OwnerUnlockResult> _attemptUnlock(
    String rtdbDeviceId, {
    required bool forceCloudKey,
  }) async {
    // 1. Challenge — a FRESH nonce per attempt: the firmware consumes
    //    it on every response, right or wrong. Older firmware has no
    //    0x0E → nothing to unlock.
    Uint8List nonce;
    try {
      nonce = await _ble.readCharacteristic(GattUuids.ownerAuth.str);
    } catch (_) {
      return OwnerUnlockResult.notRequired;
    }
    if (nonce.isEmpty) return OwnerUnlockResult.notRequired;

    // 2. Key — prefs cache, else the account's Firestore scope. On the
    //    forced-cloud retry, fall back to the cache when the fetch
    //    fails (offline), so a transient BLE error cannot cost us the
    //    only key we hold.
    final key = forceCloudKey
        ? (await _fetchCloudKey(rtdbDeviceId) ?? await _obtainKey(rtdbDeviceId))
        : await _obtainKey(rtdbDeviceId);
    if (key == null) {
      debugLog('OwnerAuth', 'No key for $rtdbDeviceId (cache + cloud)');
      return OwnerUnlockResult.noKey;
    }

    // 3. Response. The firmware rejects a wrong HMAC with an ATT
    //    authorization error, which surfaces here as a write failure.
    //    retries: false — a transport-level retry would replay the HMAC
    //    against an already-consumed nonce and read as a rejection.
    try {
      await _ble.writeCharacteristic(
        GattUuids.ownerAuth.str,
        computeUnlockResponse(key: key, nonce: nonce),
        retries: false,
      );
      debugLog('OwnerAuth', 'Unlocked $rtdbDeviceId');
      return OwnerUnlockResult.unlocked;
    } catch (e) {
      debugLog('OwnerAuth', 'Unlock rejected for $rtdbDeviceId: $e');
      return OwnerUnlockResult.locked;
    }
  }

  /// Key to install during (re-)provisioning: reuse the account's
  /// existing key for this device when one exists — so every other
  /// household phone's cached key keeps working — and generate a fresh
  /// one only for a first-time (or factory-reset + key-less) setup.
  Future<Uint8List> keyForProvisioning(String rtdbDeviceId) async {
    final existing = await _obtainKey(rtdbDeviceId);
    return existing ?? generateOwnerKey();
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
    return _fetchCloudKey(rtdbDeviceId);
  }

  /// Fetch the key from Firestore (bypassing the prefs cache) and
  /// refresh the cache on success.
  Future<Uint8List?> _fetchCloudKey(String rtdbDeviceId) async {
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
