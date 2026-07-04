import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/data/local/app_database.dart';
import 'package:gs_rework/data/local/drift_notification_repository.dart';
import 'package:gs_rework/data/local/drift_telemetry_repository.dart';
import 'package:gs_rework/domain/notifications/entities/device_notification.dart';
import 'package:gs_rework/domain/telemetry/entities/telemetry_record.dart';

void main() {
  late AppDatabase db;
  late DriftTelemetryRepository telemetry;
  late DriftNotificationRepository notifications;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    telemetry = DriftTelemetryRepository(db: db);
    notifications = DriftNotificationRepository(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  TelemetryRecord record({required int ageDays, required bool synced}) {
    return TelemetryRecord(
      deviceId: 'dev1',
      timestamp: DateTime.now().toUtc().subtract(Duration(days: ageDays)),
      temperature: 45.0,
      isOn: false,
      minTemp: 30,
      maxTemp: 60,
      synced: synced,
    );
  }

  DeviceNotification notif({required int ageDays, required bool synced}) {
    return DeviceNotification(
      deviceId: 'dev1',
      type: NotificationType.fromCode(1),
      temperature: 60,
      timestamp: DateTime.now().toUtc().subtract(Duration(days: ageDays)),
      synced: synced,
    );
  }

  group('telemetry pruneOlderThan', () {
    test('default prune deletes only SYNCED old records', () async {
      await telemetry.insertBatch([
        record(ageDays: 10, synced: true), //   old + synced   → pruned
        record(ageDays: 10, synced: false), //  old + unsynced → KEPT
        record(ageDays: 1, synced: true), //    fresh          → kept
        record(ageDays: 1, synced: false), //   fresh          → kept
      ]);

      final pruned = await telemetry.pruneOlderThan(retentionDays: 7);

      expect(pruned, 1);
      expect(await telemetry.count(), 3);
      // The old unsynced record must still be waiting for sync.
      final unsynced = await telemetry.getUnsyncedRecords();
      expect(
        unsynced.where(
          (r) => r.timestamp.isBefore(
            DateTime.now().toUtc().subtract(const Duration(days: 7)),
          ),
        ),
        hasLength(1),
      );
    });

    test('backstop prune (onlySynced: false) deletes unsynced too', () async {
      await telemetry.insertBatch([
        record(ageDays: 90, synced: false), // beyond backstop → pruned
        record(ageDays: 10, synced: false), // old but < 60d   → kept
      ]);

      final pruned = await telemetry.pruneOlderThan(
        retentionDays: 60,
        onlySynced: false,
      );

      expect(pruned, 1);
      expect(await telemetry.count(), 1);
    });
  });

  group('notification pruneOlderThan', () {
    test('default prune keeps old UNSYNCED notifications', () async {
      await notifications.insertBatch([
        notif(ageDays: 10, synced: true),
        notif(ageDays: 10, synced: false),
      ]);

      final pruned = await notifications.pruneOlderThan(retentionDays: 7);

      expect(pruned, 1);
      final remaining = await notifications.getUnsynced();
      expect(remaining, hasLength(1));
      expect(remaining.first.synced, isFalse);
    });

    test('backstop prune bounds growth regardless of sync state', () async {
      await notifications.insertBatch([
        notif(ageDays: 90, synced: false),
        notif(ageDays: 90, synced: true),
        notif(ageDays: 1, synced: false),
      ]);

      final pruned = await notifications.pruneOlderThan(
        retentionDays: 60,
        onlySynced: false,
      );

      expect(pruned, 2);
      expect(await notifications.getAll('dev1'), hasLength(1));
    });
  });
}
