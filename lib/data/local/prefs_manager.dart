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
}
