import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/ble/gatt_uuids.dart';
import '../../core/debug/debug_log.dart';
import '../../data/local/prefs_manager.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../../domain/ble/repositories/ble_repository.dart';
import '../../domain/notifications/entities/device_notification.dart';
import '../../domain/notifications/repositories/notification_repository.dart';
import '../../domain/telemetry/entities/telemetry_record.dart';
import '../../domain/telemetry/repositories/telemetry_repository.dart';

/// Background service that manages device events and notifications.
///
/// Lifecycle:
/// 1. On BLE `ready`: reads buffered events + telemetry from the ESP,
///    creates local DB records, acknowledges (clears ESP buffers),
///    then subscribes to real-time event notifications.
/// 2. On real-time event: creates a [DeviceNotification] record.
/// 3. Exposes [unreadCount] stream for the badge in the app bar.
/// 4. On BLE disconnect: unsubscribes from event notifications.
///
/// Notification preferences (per-type muting) control:
/// - Whether a notification appears in the list view
/// - Whether it counts toward the unread badge
/// - The notification is always stored and synced regardless.
///
/// All records use the canonical RTDB device ID (8-char hex), not the
/// raw BLE identifier, so BLE-delivered and FCM-delivered events share
/// the same key space and deduplication works correctly.
class NotificationService {
  NotificationService({
    required BleRepository bleRepository,
    required NotificationRepository notificationRepository,
    required TelemetryRepository telemetryRepository,
    required PrefsManager prefsManager,
  })  : _ble = bleRepository,
        _notifications = notificationRepository,
        _telemetry = telemetryRepository,
        _prefs = prefsManager;

  final BleRepository _ble;
  final NotificationRepository _notifications;
  final TelemetryRepository _telemetry;
  final PrefsManager _prefs;

  StreamSubscription<BleConnectionStatus>? _bleSub;
  StreamSubscription<Uint8List>? _eventSub;

  final _unreadCountController = StreamController<int>.broadcast();

  /// Resolve the currently connected BLE identifier to its canonical
  /// RTDB device ID.  Returns null if unmapped or disconnected.
  String? get _rtdbDeviceId {
    final bleMac = _ble.connectedDeviceId;
    if (bleMac == null) return null;
    return _prefs.getRtdbDeviceId(bleMac);
  }

  /// Stream of unread notification count (for badge UI).
  Stream<int> get unreadCount => _unreadCountController.stream;

  int _lastUnreadCount = 0;

  /// Current unread count (synchronous access).
  int get currentUnreadCount => _lastUnreadCount;

  // ── Public API ────────────────────────────────────────────────────

  /// Start monitoring BLE status and handling events.
  /// Idempotent — safe to call again after [stop] (e.g. on re-login).
  void start() {
    if (_bleSub != null) return;
    _bleSub = _ble.connectionStatus.listen(_onBleStatusChanged);

    // If already connected at start time, sync immediately.
    if (_ble.currentStatus == BleConnectionStatus.ready) {
      _syncBuffersAndSubscribe();
    }
  }

  /// Stop all monitoring. Reversible — [start] re-arms the service
  /// (sign-out stops it; a re-login in the same session must be able
  /// to bring it back). The unread stream stays open so UI listeners
  /// survive the round-trip.
  Future<void> stop() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _bleSub?.cancel();
    _bleSub = null;
    _lastUnreadCount = 0;
    if (!_unreadCountController.isClosed) {
      _unreadCountController.add(0);
    }
  }

  /// Refresh the unread count (call after dismissing or changing prefs).
  Future<void> refreshUnreadCount() async {
    final deviceId = _rtdbDeviceId;
    if (deviceId == null) return;

    final count = await _notifications.countUndismissed(
      deviceId,
      enabledTypes: _prefs.enabledNotificationTypes,
    );
    _lastUnreadCount = count;
    if (!_unreadCountController.isClosed) {
      _unreadCountController.add(count);
    }
  }

  // ── Private ───────────────────────────────────────────────────────

  void _onBleStatusChanged(BleConnectionStatus status) {
    if (status == BleConnectionStatus.ready) {
      _syncBuffersAndSubscribe();
    } else if (status == BleConnectionStatus.disconnected ||
        status == BleConnectionStatus.reconnecting) {
      _eventSub?.cancel();
      _eventSub = null;
    }
  }

  /// Full reconnect flow: read buffers → create records → ack → subscribe.
  Future<void> _syncBuffersAndSubscribe() async {
    try {
      // 1. Read buffered events from ESP.
      final eventsOk = await _syncEventBuffer();

      // 2. Read buffered telemetry from ESP.
      final telemetryOk = await _syncTelemetryBuffer();

      // 3. Acknowledge — clears both buffers on the ESP — but ONLY
      //    when both reads and inserts succeeded. One transient BLE
      //    error here must not erase a week of offline history; the
      //    buffers stay on the device for the next connect, and the
      //    sync above deduplicates by timestamp so a re-read never
      //    double-inserts.
      if (eventsOk && telemetryOk) {
        await _ackBuffers();
      } else {
        debugLog('NotificationService',
            'Buffer sync incomplete — ack withheld, retrying next connect');
      }

      // 4. Subscribe to real-time event notifications.
      _subscribeToEvents();

      // 5. Refresh badge count.
      await refreshUnreadCount();

      // 6. Prune old notifications (7-day retention).
      await _notifications.pruneOlderThan(retentionDays: 7);
    } catch (e) {
      debugLog('NotificationService', 'Buffer sync failed: $e');
    }
  }

  /// Read the event buffer characteristic and insert records.
  /// Returns true only when both the read and the insert succeeded —
  /// the caller withholds the buffer ack otherwise.
  Future<bool> _syncEventBuffer() async {
    try {
      final bytes = await _ble.readCharacteristic(
        GattUuids.deviceEvents.str,
      );
      if (bytes.isEmpty) return true;

      final deviceId = _rtdbDeviceId;
      if (deviceId == null) return false;

      final notifications = <DeviceNotification>[];

      // Each event: 6 bytes [type, temp, ts0, ts1, ts2, ts3].
      for (var i = 0; i + 5 < bytes.length; i += 6) {
        final type = bytes[i];
        final temp = bytes[i + 1];
        final ts = bytes[i + 2] |
            (bytes[i + 3] << 8) |
            (bytes[i + 4] << 16) |
            (bytes[i + 5] << 24);

        notifications.add(DeviceNotification(
          deviceId: deviceId,
          type: NotificationType.fromCode(type),
          temperature: temp,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            ts * 1000,
            isUtc: true,
          ),
        ));
      }

      if (notifications.isNotEmpty) {
        // Dedup against existing rows: a previously-failed sync leaves
        // the ESP buffer un-acked, so the same events come back on the
        // next connect. (The tables have no unique constraint.)
        final existing = await _notifications.getAll(deviceId, limit: 300);
        final seen = existing
            .map((n) => '${n.type.name}|${n.timestamp.millisecondsSinceEpoch}')
            .toSet();
        final fresh = notifications
            .where((n) => !seen.contains(
                '${n.type.name}|${n.timestamp.millisecondsSinceEpoch}'))
            .toList();
        if (fresh.isNotEmpty) {
          await _notifications.insertBatch(fresh);
        }
        debugLog('NotificationService',
            'Synced ${fresh.length} buffered events '
            '(${notifications.length - fresh.length} duplicates skipped)');
      }
      return true;
    } catch (e) {
      debugLog('NotificationService', 'Event buffer sync failed: $e');
      return false;
    }
  }

  /// Read the telemetry buffer characteristic and insert records.
  /// Returns true only when both the read and the insert succeeded —
  /// the caller withholds the buffer ack otherwise.
  Future<bool> _syncTelemetryBuffer() async {
    try {
      final bytes = await _ble.readCharacteristic(
        GattUuids.telemetryBuffer.str,
      );
      if (bytes.isEmpty) return true;

      final deviceId = _rtdbDeviceId;
      if (deviceId == null) return false;

      final records = <TelemetryRecord>[];

      // Each entry: 10 bytes
      // [temp_i16_le(2), relay(1), min(1), max(1), auto_reheat(1), ts_u32_le(4)]
      for (var i = 0; i + 9 < bytes.length; i += 10) {
        final bd = ByteData.sublistView(bytes, i, i + 10);
        final tempRaw = bd.getInt16(0, Endian.little);
        final relayOn = bytes[i + 2] == 1;
        final minTemp = bytes[i + 3];
        final maxTemp = bytes[i + 4];
        // bytes[i + 5] = auto_reheat (not stored in TelemetryRecord)
        final ts = bd.getUint32(6, Endian.little);

        records.add(TelemetryRecord(
          deviceId: deviceId,
          timestamp: DateTime.fromMillisecondsSinceEpoch(
            ts * 1000,
            isUtc: true,
          ),
          temperature: tempRaw / 100.0,
          isOn: relayOn,
          minTemp: minTemp,
          maxTemp: maxTemp,
        ));
      }

      if (records.isNotEmpty) {
        // Dedup by timestamp — see _syncEventBuffer.
        final existing = await _telemetry.getRecords(deviceId, limit: 300);
        final seen = existing
            .map((r) => r.timestamp.millisecondsSinceEpoch)
            .toSet();
        final fresh = records
            .where((r) => !seen.contains(r.timestamp.millisecondsSinceEpoch))
            .toList();
        if (fresh.isNotEmpty) {
          await _telemetry.insertBatch(fresh);
        }
        debugLog('NotificationService',
            'Synced ${fresh.length} buffered telemetry entries '
            '(${records.length - fresh.length} duplicates skipped)');
      }
      return true;
    } catch (e) {
      debugLog('NotificationService', 'Telemetry buffer sync failed: $e');
      return false;
    }
  }

  /// Write ack to clear both buffers on the ESP.
  Future<void> _ackBuffers() async {
    try {
      await _ble.writeCharacteristic(
        GattUuids.bufferAck.str,
        Uint8List.fromList([0x01]),
      );
      debugLog('NotificationService', 'Buffer acknowledge sent');
    } catch (e) {
      debugLog('NotificationService', 'Buffer ack failed: $e');
    }
  }

  /// Subscribe to real-time event notifications via BLE.
  void _subscribeToEvents() {
    _eventSub?.cancel();
    _eventSub = _ble.subscribe(GattUuids.deviceEvents.str).listen(
      (bytes) {
        if (bytes.length < 2) return;

        final deviceId = _rtdbDeviceId;
        if (deviceId == null) return;

        final type = NotificationType.fromCode(bytes[0]);
        final temp = bytes[1];

        final notification = DeviceNotification(
          deviceId: deviceId,
          type: type,
          temperature: temp,
          timestamp: DateTime.now().toUtc(),
          source: NotificationSource.ble,
        );

        // Always store, regardless of mute preferences.
        _notifications.insert(notification).then((_) {
          // Only increment badge if this type is enabled.
          if (_prefs.isNotificationTypeEnabled(type)) {
            _lastUnreadCount++;
            if (!_unreadCountController.isClosed) {
              _unreadCountController.add(_lastUnreadCount);
            }
          }

          debugLog('NotificationService',
              'Real-time event: ${type.label} @ $temp°C');
        }).catchError((Object e) {
          // Contained: an unhandled error here would surface as a
          // fatal zone error via Crashlytics.
          debugLog('NotificationService', 'Real-time insert failed: $e');
        });
      },
    );
  }
}
