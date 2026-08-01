import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/notifications/entities/device_notification.dart';

/// Single source of truth for all SharedPreferences access.
///
/// Call [PrefsManager.create] once during DI setup (async), then
/// inject the instance everywhere.  Reads are synchronous (cached).
class PrefsManager {
  PrefsManager._(this._prefs);

  /// Factory — must be awaited during DI init.
  static Future<PrefsManager> create() async {
    final prefs = await SharedPreferences.getInstance();
    return PrefsManager._(prefs);
  }

  final SharedPreferences _prefs;

  // ── BLE Pairing ──────────────────────────────────────────────────

  static const _kPairedId = 'ble_paired_device_id';
  static const _kPairedName = 'ble_paired_device_name';

  String? get pairedDeviceId => _prefs.getString(_kPairedId);
  String? get pairedDeviceName => _prefs.getString(_kPairedName);

  Future<void> setPairedDevice(String id, String name) async {
    await _prefs.setString(_kPairedId, id);
    await _prefs.setString(_kPairedName, name);
  }

  Future<void> clearPairedDevice() async {
    await _prefs.remove(_kPairedId);
    await _prefs.remove(_kPairedName);
  }

  /// Re-read values from the platform store. Needed before checking
  /// flags that the workmanager background isolate may have written
  /// through its own SharedPreferences instance (this isolate's cache
  /// would otherwise be stale).
  Future<void> reload() => _prefs.reload();

  // ── Sync Orchestrator ────────────────────────────────────────────

  static const _kPendingRetry = 'sync_pending_wifi_retry';
  static const _kLastSync = 'sync_last_success';

  bool get hasPendingRetry => _prefs.getBool(_kPendingRetry) ?? false;
  String? get lastSyncTime => _prefs.getString(_kLastSync);

  Future<void> setPendingRetry(bool pending) async {
    if (pending) {
      await _prefs.setBool(_kPendingRetry, true);
    } else {
      await _prefs.remove(_kPendingRetry);
    }
  }

  Future<void> setLastSyncTime(DateTime time) async {
    await _prefs.setString(_kLastSync, time.toUtc().toIso8601String());
  }

  // ── BLE owner key cache ──────────────────────────────────────────
  //
  // Base64 of the 32-byte device key, cached per RTDB device ID after
  // the first Firestore fetch so BLE unlock works fully offline.

  static const _kOwnerKeyPrefix = 'ble_owner_key_';

  String? getBleOwnerKey(String rtdbDeviceId) =>
      _prefs.getString('$_kOwnerKeyPrefix$rtdbDeviceId');

  Future<void> setBleOwnerKey(String rtdbDeviceId, String base64Key) async {
    await _prefs.setString('$_kOwnerKeyPrefix$rtdbDeviceId', base64Key);
  }

  // ── Notification Preferences ─────────────────────────────────────

  static const _kNotifPrefix = 'notif_enabled_';

  /// Whether a specific notification type is enabled (default: true).
  bool isNotificationTypeEnabled(NotificationType type) {
    return _prefs.getBool('$_kNotifPrefix${type.name}') ?? true;
  }

  /// Toggle a specific notification type on/off.
  Future<void> setNotificationTypeEnabled(
    NotificationType type,
    bool enabled,
  ) {
    return _prefs.setBool('$_kNotifPrefix${type.name}', enabled);
  }

  /// All currently enabled notification types.
  Set<NotificationType> get enabledNotificationTypes {
    return NotificationType.values
        .where((t) => isNotificationTypeEnabled(t))
        .toSet();
  }

  /// Whether at least one notification type is enabled.
  bool get anyNotificationEnabled =>
      NotificationType.values.any(isNotificationTypeEnabled);

  // ── Device ID Mapping ────────────────────────────────────────────
  //
  // Maps BLE MAC/UUID to RTDB device IDs.  Each physical device gets
  // a deterministic RTDB ID derived from its MAC at provisioning.
  // Key format: "rtdb_did_{sanitised_ble_mac}"

  static const _kRtdbDidPrefix = 'rtdb_did_';

  /// Get the RTDB device ID for a given BLE MAC.  Returns null if
  /// this device hasn't been provisioned through this app.
  String? getRtdbDeviceId(String bleMac) {
    final key = '$_kRtdbDidPrefix${_sanitiseMac(bleMac)}';
    return _prefs.getString(key);
  }

  /// Store the RTDB device ID for a BLE MAC after provisioning.
  Future<void> setRtdbDeviceId(String bleMac, String rtdbDeviceId) async {
    final key = '$_kRtdbDidPrefix${_sanitiseMac(bleMac)}';
    await _prefs.setString(key, rtdbDeviceId);
  }

  /// List all known RTDB device IDs (for building the device list).
  List<String> getAllRtdbDeviceIds() {
    return _prefs
        .getKeys()
        .where((k) => k.startsWith(_kRtdbDidPrefix))
        .map((k) => _prefs.getString(k)!)
        .toList();
  }

  /// Returns all (bleMac → rtdbDeviceId) pairs for building the registry.
  Map<String, String> getAllDeviceMappings() {
    final map = <String, String>{};
    for (final key in _prefs.getKeys()) {
      if (key.startsWith(_kRtdbDidPrefix)) {
        final mac = key.substring(_kRtdbDidPrefix.length).replaceAll('_', ':');
        map[mac] = _prefs.getString(key)!;
      }
    }
    return map;
  }

  static String _sanitiseMac(String mac) => mac.replaceAll(':', '_');

  // ── Device Nicknames ─────────────────────────────────────────────
  //
  // Persists the user-visible nickname for each device so the
  // DeviceRegistry can display it even when BLE is disconnected.

  static const _kDeviceNickPrefix = 'dev_nick_';

  String? getDeviceNickname(String rtdbDeviceId) {
    return _prefs.getString('$_kDeviceNickPrefix$rtdbDeviceId');
  }

  Future<void> setDeviceNickname(String rtdbDeviceId, String nickname) async {
    await _prefs.setString('$_kDeviceNickPrefix$rtdbDeviceId', nickname);
  }

  /// Remove a device mapping and its nickname.
  Future<void> removeDevice(String bleMac, String rtdbDeviceId) async {
    final key = '$_kRtdbDidPrefix${_sanitiseMac(bleMac)}';
    await _prefs.remove(key);
    await _prefs.remove('$_kDeviceNickPrefix$rtdbDeviceId');
  }

  // ── Sign-out cleanup ──────────────────────────────────────────────

  /// Remove all device mappings, nicknames, cached BLE owner keys, and
  /// pairing data. Called on sign-out so the next user starts fresh.
  ///
  /// The owner keys MUST go: they are what proves this phone belongs to
  /// the previous account's household. Leaving them behind would let
  /// the next person to sign in on this handset unlock — and re-bind —
  /// the previous owner's geyser, and would let it be copied into their
  /// cloud scope on the next provisioning.
  Future<void> clearDeviceData() async {
    final keysToRemove = _prefs.getKeys().where((k) =>
        k.startsWith(_kRtdbDidPrefix) ||
        k.startsWith(_kOwnerKeyPrefix) ||
        k.startsWith(_kDeviceNickPrefix));
    for (final key in keysToRemove.toList()) {
      await _prefs.remove(key);
    }
    await clearPairedDevice();
  }
}
