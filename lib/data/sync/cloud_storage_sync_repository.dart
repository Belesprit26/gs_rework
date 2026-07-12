import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../core/debug/debug_log.dart';
import '../../domain/notifications/entities/device_notification.dart';
import '../../domain/notifications/repositories/notification_repository.dart';
import '../../domain/telemetry/entities/telemetry_record.dart';
import '../../domain/telemetry/repositories/telemetry_repository.dart';
import '../../domain/telemetry/repositories/telemetry_sync_repository.dart';
import 'ndjson_codec.dart';

/// Syncs telemetry AND notifications to Firebase Cloud Storage as
/// immutable, append-only NDJSON chunk objects:
///
///   `telemetry/{userId}/{deviceId}/{utcTimestamp}_{nonce}.ndjson.gz`
///
/// Each sync uploads only the unsynced records as a NEW object and
/// never reads or rewrites existing ones. This is what makes the sync
/// durable:
///
/// - No read-modify-write → concurrent syncs (main isolate vs
///   workmanager isolate, or two phones on one account) can never
///   clobber each other's data. Worst case is a duplicate chunk.
/// - No download step → no size ceiling, no re-uploading history,
///   bandwidth stays proportional to new data.
/// - Records are marked synced only AFTER a successful upload, so a
///   crash in between re-uploads them into a new chunk (duplicate
///   lines — each line carries `did` + `ts`, so consumers can dedup)
///   rather than losing them.
///
/// Record kinds share the chunk, differentiated by the `k` field:
/// `"t"` for telemetry, `"n"` for notifications.
///
/// The pre-chunking merged file (`telemetry/{userId}/{deviceId}.ndjson.gz`)
/// is left untouched as a historical archive; nothing reads or writes
/// it anymore.
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

  /// Max records per table per pass (bounds chunk size and memory).
  static const int _batchLimit = 5000;

  /// Max drain passes per sync run (safety valve; a backlog beyond
  /// this simply continues on the next run).
  static const int _maxPasses = 20;

  static final Random _random = Random();

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

    var total = 0;
    // Devices that failed this run — skipped on subsequent passes so
    // one broken device can't stall the drain loop.
    final failedDevices = <String, Object>{};

    for (var pass = 0; pass < _maxPasses; pass++) {
      final telemetryRecords =
          await _telemetry.getUnsyncedRecords(limit: _batchLimit);
      final notifRecords =
          await _notifications.getUnsynced(limit: _batchLimit);

      if (telemetryRecords.isEmpty && notifRecords.isEmpty) break;

      final syncedThisPass = await _syncPass(
        userId: user.uid,
        telemetryRecords: telemetryRecords,
        notifRecords: notifRecords,
        failedDevices: failedDevices,
      );
      total += syncedThisPass;

      // Only failing devices' records remain → stop retrying this run.
      if (syncedThisPass == 0) break;

      // Both tables returned less than a full batch → drained.
      if (telemetryRecords.length < _batchLimit &&
          notifRecords.length < _batchLimit) {
        break;
      }
    }

    if (failedDevices.isNotEmpty) {
      // Successfully synced records are already marked, so retrying
      // later only re-attempts what actually failed.
      throw StateError(
          'Sync incomplete: $total records synced, but upload failed for '
          'device(s) ${failedDevices.keys.join(', ')} — '
          'first error: ${failedDevices.values.first}');
    }

    return total;
  }

  // ── Private ───────────────────────────────────────────────────────

  /// Upload one gathered batch, device by device. Failures are recorded
  /// in [failedDevices] and do not affect other devices.
  /// Returns the number of records synced in this pass.
  Future<int> _syncPass({
    required String userId,
    required List<TelemetryRecord> telemetryRecords,
    required List<DeviceNotification> notifRecords,
    required Map<String, Object> failedDevices,
  }) async {
    // Group both record types by device ID.
    final telemetryByDevice = <String, List<TelemetryRecord>>{};
    for (final r in telemetryRecords) {
      telemetryByDevice.putIfAbsent(r.deviceId, () => []).add(r);
    }
    final notifByDevice = <String, List<DeviceNotification>>{};
    for (final r in notifRecords) {
      notifByDevice.putIfAbsent(r.deviceId, () => []).add(r);
    }

    final allDevices = {...telemetryByDevice.keys, ...notifByDevice.keys};
    final pushDate =
        DateTime.now().toUtc().toIso8601String().split('T').first;

    var synced = 0;

    for (final deviceId in allDevices) {
      if (failedDevices.containsKey(deviceId)) continue;

      final deviceTelemetry = telemetryByDevice[deviceId] ?? const [];
      final deviceNotifs = notifByDevice[deviceId] ?? const [];

      final telemetryIds = [
        for (final r in deviceTelemetry)
          if (r.id != null) r.id!,
      ];
      final notifIds = [
        for (final r in deviceNotifs)
          if (r.id != null) r.id!,
      ];

      try {
        final ndjson =
            (deviceTelemetry.isNotEmpty
                    ? NdjsonCodec.encodeTelemetry(deviceTelemetry,
                        pushDate: pushDate)
                    : '') +
                (deviceNotifs.isNotEmpty
                    ? NdjsonCodec.encodeNotifications(deviceNotifs,
                        pushDate: pushDate)
                    : '');
        if (ndjson.trim().isEmpty) continue;

        await _uploadChunk(
          userId: userId,
          deviceId: deviceId,
          ndjson: ndjson,
          pushDate: pushDate,
        );

        // Mark synced only after the upload succeeded.
        if (telemetryIds.isNotEmpty) await _telemetry.markSynced(telemetryIds);
        if (notifIds.isNotEmpty) await _notifications.markSynced(notifIds);
        synced += telemetryIds.length + notifIds.length;

        debugLog(
            'Sync',
            'Chunk uploaded: ${telemetryIds.length} telemetry + '
            '${notifIds.length} notifications for device $deviceId');
      } catch (e) {
        failedDevices[deviceId] = e;
        debugLog('Sync', 'Failed for device $deviceId: $e');
      }
    }

    return synced;
  }

  Future<void> _uploadChunk({
    required String userId,
    required String deviceId,
    required String ndjson,
    required String pushDate,
  }) async {
    final path = chunkPath(
      userId: userId,
      deviceId: deviceId,
      utc: DateTime.now().toUtc(),
      nonce: _nonce(),
    );

    final lineCount = ndjson.split('\n').where((l) => l.isNotEmpty).length;

    await _storage.ref(path).putData(
          NdjsonCodec.gzipEncode(ndjson),
          SettableMetadata(
            contentType: 'application/gzip',
            customMetadata: {
              'pushDate': pushDate,
              'lines': lineCount.toString(),
            },
          ),
        );
  }

  /// 4 hex chars so two writers in the same second (e.g. two phones on
  /// one account) still produce distinct object names.
  static String _nonce() =>
      _random.nextInt(0x10000).toRadixString(16).padLeft(4, '0');

  /// Object path for one chunk:
  /// `telemetry/{userId}/{safeDeviceId}/{yyyyMMddTHHmmssZ}_{nonce}.ndjson.gz`
  ///
  /// The timestamp prefix keeps chunks lexically sortable by upload
  /// time; the device ID is sanitized for use as a path segment.
  @visibleForTesting
  static String chunkPath({
    required String userId,
    required String deviceId,
    required DateTime utc,
    required String nonce,
  }) {
    final safeDeviceId = deviceId.replaceAll(':', '-');
    String two(int v) => v.toString().padLeft(2, '0');
    final ts = '${utc.year}${two(utc.month)}${two(utc.day)}'
        'T${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
    return 'telemetry/$userId/$safeDeviceId/${ts}_$nonce.ndjson.gz';
  }
}
