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

  // ── Heat mode (per device) ───────────────────────────────────────
  //
  // "Heat for a time" is an app-level preset over existing controls: it
  // parks the temperature ceiling at its maximum and turns Auto-Reheat
  // off, then leans on the user's timers + Max continuous run. We persist
  // the mode plus the temperature-mode max / auto-reheat so switching back
  // restores exactly what they had. Keyed by RTDB device id; wiped on
  // device removal and sign-out.

  static const _kHeatTimeModePrefix = 'heat_time_mode_';
  static const _kHeatSavedMaxPrefix = 'heat_saved_max_';
  static const _kHeatSavedArPrefix = 'heat_saved_ar_';

  /// Whether this device is in "Heat for a time" mode (default: false —
  /// "Heat to a temperature").
  bool isTimeHeatMode(String rtdbDeviceId) =>
      _prefs.getBool('$_kHeatTimeModePrefix$rtdbDeviceId') ?? false;

  /// The temperature-mode max °C to restore when leaving time mode.
  int? savedHeatMax(String rtdbDeviceId) =>
      _prefs.getInt('$_kHeatSavedMaxPrefix$rtdbDeviceId');

  /// The temperature-mode auto-reheat state to restore when leaving.
  bool? savedHeatAutoReheat(String rtdbDeviceId) =>
      _prefs.getBool('$_kHeatSavedArPrefix$rtdbDeviceId');

  /// Enter time mode, remembering the temperature-mode limits to restore.
  Future<void> enableTimeHeatMode(
    String rtdbDeviceId, {
    required int savedMax,
    required bool savedAutoReheat,
  }) async {
    await _prefs.setBool('$_kHeatTimeModePrefix$rtdbDeviceId', true);
    await _prefs.setInt('$_kHeatSavedMaxPrefix$rtdbDeviceId', savedMax);
    await _prefs.setBool('$_kHeatSavedArPrefix$rtdbDeviceId', savedAutoReheat);
  }

  /// Leave time mode; the remembered limits are no longer needed.
  Future<void> disableTimeHeatMode(String rtdbDeviceId) async {
    await _prefs.remove('$_kHeatTimeModePrefix$rtdbDeviceId');
    await _prefs.remove('$_kHeatSavedMaxPrefix$rtdbDeviceId');
    await _prefs.remove('$_kHeatSavedArPrefix$rtdbDeviceId');
  }

  // ── Sensor declaration (Sensors card) ─────────────────────────────
  //
  // What the user says is physically installed on this unit. Local
  // mirror of the RTDB `set/$did` keys `cs`/`ls` (the cross-phone
  // authority) so BLE-only installs and offline reads still work.
  // Temperature has no flag — it ships in every package (locked ON).
  // Defaults: current NO · leak NO. Keyed by RTDB device id; wiped on
  // device removal and sign-out.

  static const _kHasCurrentPrefix = 'sensor_current_';
  static const _kHasLeakPrefix = 'sensor_leak_';

  /// Whether this unit has a current (power-measuring) sensor.
  bool hasCurrentSensor(String rtdbDeviceId) =>
      _prefs.getBool('$_kHasCurrentPrefix$rtdbDeviceId') ?? false;

  /// Whether this unit has a leak-detection probe.
  bool hasLeakSensor(String rtdbDeviceId) =>
      _prefs.getBool('$_kHasLeakPrefix$rtdbDeviceId') ?? false;

  Future<void> setHasCurrentSensor(String rtdbDeviceId, bool v) async {
    await _prefs.setBool('$_kHasCurrentPrefix$rtdbDeviceId', v);
  }

  Future<void> setHasLeakSensor(String rtdbDeviceId, bool v) async {
    await _prefs.setBool('$_kHasLeakPrefix$rtdbDeviceId', v);
  }

  // ── Device last-seen (connectivity badge) ─────────────────────────
  //
  // Local copy of the last moment we were in contact with a device by
  // ANY path (BLE ready, or a fresh RTDB heartbeat). Gives BLE-only
  // devices a real "down for X" figure and survives app restarts, where
  // the cubit's RTDB-fed lastSeen starts null. Keyed by RTDB device id;
  // wiped on device removal and sign-out.

  static const _kLastSeenPrefix = 'device_last_seen_';

  /// The last locally-recorded contact with this device, if any.
  DateTime? deviceLastSeenLocal(String rtdbDeviceId) {
    final ms = _prefs.getInt('$_kLastSeenPrefix$rtdbDeviceId');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// Record a moment of contact with this device.
  Future<void> setDeviceLastSeenLocal(
    String rtdbDeviceId,
    DateTime at,
  ) async {
    await _prefs.setInt(
      '$_kLastSeenPrefix$rtdbDeviceId',
      at.millisecondsSinceEpoch,
    );
  }

  /// Remove a device mapping and its nickname.
  Future<void> removeDevice(String bleMac, String rtdbDeviceId) async {
    final key = '$_kRtdbDidPrefix${_sanitiseMac(bleMac)}';
    await _prefs.remove(key);
    await _prefs.remove('$_kDeviceNickPrefix$rtdbDeviceId');
    await disableTimeHeatMode(rtdbDeviceId);
    await _prefs.remove('$_kLastSeenPrefix$rtdbDeviceId');
    await _prefs.remove('$_kHasCurrentPrefix$rtdbDeviceId');
    await _prefs.remove('$_kHasLeakPrefix$rtdbDeviceId');
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
        k.startsWith(_kDeviceNickPrefix) ||
        k.startsWith(_kHeatTimeModePrefix) ||
        k.startsWith(_kHeatSavedMaxPrefix) ||
        k.startsWith(_kHeatSavedArPrefix) ||
        k.startsWith(_kLastSeenPrefix) ||
        k.startsWith(_kHasCurrentPrefix) ||
        k.startsWith(_kHasLeakPrefix));
    for (final key in keysToRemove.toList()) {
      await _prefs.remove(key);
    }
    await clearPairedDevice();
  }
}
