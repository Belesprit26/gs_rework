import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../domain/notifications/entities/device_notification.dart';
import '../../domain/notifications/repositories/notification_repository.dart';
import '../../domain/telemetry/entities/telemetry_record.dart';
import '../../domain/telemetry/repositories/telemetry_repository.dart';
import '../../domain/telemetry/repositories/telemetry_sync_repository.dart';
import 'ndjson_codec.dart';

/// Syncs telemetry AND notifications to Firebase Cloud Storage as a
/// single NDJSON file per device.
///
/// File path: `telemetry/{userId}/{deviceId}.ndjson.gz`
///
/// Both record types are differentiated by the `k` (kind) field:
/// - `"t"` for telemetry
/// - `"n"` for notifications
///
/// Strategy:
/// 1. Query all unsynced telemetry + notification records.
/// 2. Group by device ID.
/// 3. For each device:
///    a. Download existing file (if any).
///    b. Decode (gunzip).
///    c. Append new NDJSON lines (both telemetry and notifications).
///    d. Re-encode (gzip).
///    e. Upload back to Cloud Storage.
/// 4. Mark local records as synced.
class CloudStorageSyncRepository implements TelemetrySyncRepository {
  CloudStorageSyncRepository({
    required FirebaseStorage storage,
    required FirebaseAuth auth,
    required TelemetryRepository telemetryRepository,
    required NotificationRepository notificationRepository,
  })  : _storage = storage,
        _auth = auth,
        _telemetry = telemetryRepository,
        _notifications = notificationRepository;

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;
  final TelemetryRepository _telemetry;
  final NotificationRepository _notifications;

  /// Max records per sync batch (safety valve).
  static const int _batchLimit = 5000;

  /// Max download size for existing file (10 MB).
  static const int _maxDownloadBytes = 10 * 1024 * 1024;

  @override
  Future<bool> get hasPendingRecords async {
    final telemetry = await _telemetry.getUnsyncedRecords(limit: 1);
    if (telemetry.isNotEmpty) return true;
    final notifs = await _notifications.getUnsynced(limit: 1);
    return notifs.isNotEmpty;
  }

  @override
  Future<int> syncUnsyncedRecords() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Cannot sync: no authenticated user');
    }

    // Gather unsynced records from both tables.
    final telemetryRecords =
        await _telemetry.getUnsyncedRecords(limit: _batchLimit);
    final notifRecords =
        await _notifications.getUnsynced(limit: _batchLimit);

    if (telemetryRecords.isEmpty && notifRecords.isEmpty) return 0;

    // Group by device ID.
    final telemetryByDevice = <String, List<TelemetryRecord>>{};
    final telemetryIdsByDevice = <String, List<int>>{};
    for (final r in telemetryRecords) {
      telemetryByDevice.putIfAbsent(r.deviceId, () => []).add(r);
      if (r.id != null) {
        telemetryIdsByDevice.putIfAbsent(r.deviceId, () => []).add(r.id!);
      }
    }

    final notifByDevice = <String, List<DeviceNotification>>{};
    final notifIdsByDevice = <String, List<int>>{};
    for (final r in notifRecords) {
      notifByDevice.putIfAbsent(r.deviceId, () => []).add(r);
      if (r.id != null) {
        notifIdsByDevice.putIfAbsent(r.deviceId, () => []).add(r.id!);
      }
    }

    // All device IDs from both tables.
    final allDevices = {...telemetryByDevice.keys, ...notifByDevice.keys};

    final pushDate =
        DateTime.now().toUtc().toIso8601String().split('T').first;
    int totalSynced = 0;

    for (final deviceId in allDevices) {
      final deviceTelemetry = telemetryByDevice[deviceId] ?? [];
      final deviceNotifs = notifByDevice[deviceId] ?? [];
      final telemetryIds = telemetryIdsByDevice[deviceId] ?? [];
      final notifIds = notifIdsByDevice[deviceId] ?? [];

      try {
        // Encode both types into NDJSON.
        final telemetryNdjson = deviceTelemetry.isNotEmpty
            ? NdjsonCodec.encodeTelemetry(deviceTelemetry, pushDate: pushDate)
            : '';
        final notifNdjson = deviceNotifs.isNotEmpty
            ? NdjsonCodec.encodeNotifications(deviceNotifs, pushDate: pushDate)
            : '';
        final combined = '$telemetryNdjson$notifNdjson';

        if (combined.trim().isEmpty) continue;

        await _syncDeviceFile(
          userId: user.uid,
          deviceId: deviceId,
          newNdjson: combined,
        );

        // Mark as synced only after successful upload.
        if (telemetryIds.isNotEmpty) {
          await _telemetry.markSynced(telemetryIds);
        }
        if (notifIds.isNotEmpty) {
          await _notifications.markSynced(notifIds);
        }
        totalSynced += telemetryIds.length + notifIds.length;

        if (kDebugMode) {
          debugPrint('[Sync] Pushed ${telemetryIds.length} telemetry + '
              '${notifIds.length} notifications for device $deviceId');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Sync] Failed for device $deviceId: $e');
        }
        rethrow;
      }
    }

    return totalSynced;
  }

  // ── Private ───────────────────────────────────────────────────────

  Future<void> _syncDeviceFile({
    required String userId,
    required String deviceId,
    required String newNdjson,
  }) async {
    // Sanitize device ID for use as a file name (replace colons).
    final safeDeviceId = deviceId.replaceAll(':', '-');
    final path = 'telemetry/$userId/$safeDeviceId.ndjson.gz';
    final ref = _storage.ref(path);

    // 1. Download existing file (if any).
    String? existingNdjson;
    try {
      final data = await ref.getData(_maxDownloadBytes);
      if (data != null && data.isNotEmpty) {
        existingNdjson = NdjsonCodec.gzipDecode(data);
      }
    } on FirebaseException catch (e) {
      // File doesn't exist yet — that's fine, we'll create it.
      if (e.code != 'object-not-found') rethrow;
    }

    // 2. Append new content.
    final merged = NdjsonCodec.append(existingNdjson, newNdjson);

    // 3. Gzip and upload.
    final compressed = NdjsonCodec.gzipEncode(merged);
    await ref.putData(
      Uint8List.fromList(compressed),
      SettableMetadata(
        contentType: 'application/gzip',
        customMetadata: {
          'lastPushDate': DateTime.now().toUtc().toIso8601String().split('T').first,
          'totalLines':
              merged.split('\n').where((l) => l.isNotEmpty).length.toString(),
        },
      ),
    );
  }
}
