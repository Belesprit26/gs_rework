import 'package:drift/drift.dart';

import '../../domain/notifications/entities/device_notification.dart';
import '../../domain/notifications/repositories/notification_repository.dart';
import 'app_database.dart';

/// Drift/SQLite implementation of [NotificationRepository].
class DriftNotificationRepository implements NotificationRepository {
  DriftNotificationRepository({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  // ── Write ─────────────────────────────────────────────────────────

  @override
  Future<void> insert(DeviceNotification notification) async {
    await _db.into(_db.notificationEntries).insert(
          _toCompanion(notification),
        );
  }

  @override
  Future<void> insertBatch(List<DeviceNotification> notifications) async {
    await _db.batch((batch) {
      batch.insertAll(
        _db.notificationEntries,
        notifications.map(_toCompanion).toList(),
      );
    });
  }

  // ── Read ──────────────────────────────────────────────────────────

  @override
  Future<List<DeviceNotification>> getAll(
    String deviceId, {
    int? limit,
  }) async {
    final query = _db.select(_db.notificationEntries)
      ..where((t) => t.deviceId.equals(deviceId))
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);

    if (limit != null) query.limit(limit);

    final rows = await query.get();
    return rows.map(_fromEntry).toList();
  }

  @override
  Future<List<DeviceNotification>> getUndismissed(String deviceId) async {
    final query = _db.select(_db.notificationEntries)
      ..where(
        (t) => t.deviceId.equals(deviceId) & t.dismissed.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);

    final rows = await query.get();
    return rows.map(_fromEntry).toList();
  }

  @override
  Future<int> countUndismissed(
    String deviceId, {
    Set<NotificationType>? enabledTypes,
  }) async {
    final countExpr = _db.notificationEntries.id.count();
    final query = _db.selectOnly(_db.notificationEntries)
      ..addColumns([countExpr])
      ..where(
        _db.notificationEntries.deviceId.equals(deviceId) &
            _db.notificationEntries.dismissed.equals(false),
      );

    if (enabledTypes != null && enabledTypes.isNotEmpty) {
      query.where(
        _db.notificationEntries.type.isIn(
          enabledTypes.map((e) => e.code).toList(),
        ),
      );
    }

    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  @override
  Future<bool> hasMatchingEvent({
    required String deviceId,
    required NotificationType type,
    required DateTime timestamp,
    Duration window = const Duration(minutes: 2),
  }) async {
    final lower = timestamp.subtract(window);
    final upper = timestamp.add(window);

    final countExpr = _db.notificationEntries.id.count();
    final query = _db.selectOnly(_db.notificationEntries)
      ..addColumns([countExpr])
      ..where(
        _db.notificationEntries.deviceId.equals(deviceId) &
            _db.notificationEntries.type.equals(type.code) &
            _db.notificationEntries.timestamp
                .isBiggerOrEqualValue(lower) &
            _db.notificationEntries.timestamp
                .isSmallerOrEqualValue(upper),
      );

    final result = await query.getSingle();
    return (result.read(countExpr) ?? 0) > 0;
  }

  @override
  Future<List<DeviceNotification>> getUnsynced({int? limit}) async {
    final query = _db.select(_db.notificationEntries)
      ..where((t) => t.synced.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);

    if (limit != null) query.limit(limit);

    final rows = await query.get();
    return rows.map(_fromEntry).toList();
  }

  // ── Update ────────────────────────────────────────────────────────

  @override
  Future<void> markDismissed(int id) async {
    await (_db.update(_db.notificationEntries)
          ..where((t) => t.id.equals(id)))
        .write(const NotificationEntriesCompanion(
      dismissed: Value(true),
    ));
  }

  @override
  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await (_db.update(_db.notificationEntries)
          ..where((t) => t.id.isIn(ids)))
        .write(const NotificationEntriesCompanion(
      synced: Value(true),
    ));
  }

  // ── Maintenance ───────────────────────────────────────────────────

  @override
  Future<int> pruneOlderThan({
    int retentionDays = 7,
    bool onlySynced = true,
  }) async {
    final cutoff =
        DateTime.now().toUtc().subtract(Duration(days: retentionDays));
    final query = _db.delete(_db.notificationEntries)
      ..where((t) => t.timestamp.isSmallerThanValue(cutoff));
    if (onlySynced) {
      query.where((t) => t.synced.equals(true));
    }
    return await query.go();
  }

  @override
  Future<void> deleteAll() async {
    await _db.delete(_db.notificationEntries).go();
  }

  // ── Private: mapping ──────────────────────────────────────────────

  static NotificationEntriesCompanion _toCompanion(DeviceNotification n) {
    return NotificationEntriesCompanion.insert(
      deviceId: n.deviceId,
      type: n.type.code,
      temperature: n.temperature,
      timestamp: n.timestamp,
      dismissed: Value(n.dismissed),
      synced: Value(n.synced),
      source: Value(n.source == NotificationSource.remote ? 'remote' : 'ble'),
    );
  }

  static DeviceNotification _fromEntry(NotificationEntry e) {
    return DeviceNotification(
      id: e.id,
      deviceId: e.deviceId,
      type: NotificationType.fromCode(e.type),
      temperature: e.temperature,
      timestamp: e.timestamp,
      dismissed: e.dismissed,
      synced: e.synced,
      source:
          e.source == 'remote' ? NotificationSource.remote : NotificationSource.ble,
    );
  }
}
