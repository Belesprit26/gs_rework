import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/data/local/app_database.dart';
import 'package:gs_rework/data/local/drift_notification_repository.dart';
import 'package:gs_rework/domain/notifications/entities/device_notification.dart';

/// Locks the v3 → v4 migration that adds `read` to notification_entries.
///
/// The risk this guards is upgrade-only and invisible in a fresh install:
/// `read` defaults to false, so without the backfill every notification a
/// user already has would become unread the moment they update, greeting
/// them with a badge counting weeks of events they dealt with long ago.
///
/// `NativeDatabase.memory(setup:)` runs before drift opens the database, so
/// the v3 schema is built by hand and stamped with `user_version = 3`;
/// drift then sees an old database and runs the real onUpgrade path.
void main() {
  /// The exact shape of notification_entries at schema v3 — v4 minus the
  /// `read` column.
  const v3NotificationEntries = '''
    CREATE TABLE "notification_entries" (
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      "device_id" TEXT NOT NULL,
      "type" INTEGER NOT NULL,
      "temperature" INTEGER NOT NULL,
      "timestamp" INTEGER NOT NULL,
      "dismissed" INTEGER NOT NULL DEFAULT 0 CHECK ("dismissed" IN (0, 1)),
      "synced" INTEGER NOT NULL DEFAULT 0 CHECK ("synced" IN (0, 1)),
      "source" TEXT NOT NULL DEFAULT 'ble'
    )''';

  const v3TelemetryEntries = '''
    CREATE TABLE "telemetry_entries" (
      "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      "device_id" TEXT NOT NULL,
      "timestamp" INTEGER NOT NULL,
      "temperature" REAL NOT NULL,
      "is_on" INTEGER NOT NULL DEFAULT 0 CHECK ("is_on" IN (0, 1)),
      "min_temp" INTEGER NOT NULL DEFAULT 30,
      "max_temp" INTEGER NOT NULL DEFAULT 60,
      "synced" INTEGER NOT NULL DEFAULT 0 CHECK ("synced" IN (0, 1))
    )''';

  /// Opens a database that already holds [existingRows] pre-upgrade
  /// notifications, then lets drift migrate it to the current schema.
  AppDatabase openUpgradedFromV3({required int existingRows, int dismissed = 0}) {
    return AppDatabase.forTesting(NativeDatabase.memory(setup: (raw) {
      raw.execute(v3NotificationEntries);
      raw.execute(v3TelemetryEntries);
      for (var i = 0; i < existingRows; i++) {
        raw.execute(
          'INSERT INTO notification_entries '
          '(device_id, type, temperature, timestamp, dismissed, synced, source) '
          "VALUES ('dev1', ${NotificationType.maxTempOff.code}, 60, "
          "strftime('%s','now'), ${i < dismissed ? 1 : 0}, 0, 'ble')",
        );
      }
      raw.execute('PRAGMA user_version = 3');
    }));
  }

  test('existing notifications survive the upgrade', () async {
    final db = openUpgradedFromV3(existingRows: 3);
    final repo = DriftNotificationRepository(db: db);

    expect((await repo.getAllUndismissed()).length, 3);

    await db.close();
  });

  test('existing notifications are backfilled as read', () async {
    final db = openUpgradedFromV3(existingRows: 3);
    final repo = DriftNotificationRepository(db: db);

    // Without the backfill this is 3, and the user opens the app after an
    // update to a badge full of events they have already handled.
    expect(await repo.countAllUnread(), 0);

    await db.close();
  });

  test('dismissed rows stay dismissed across the upgrade', () async {
    final db = openUpgradedFromV3(existingRows: 3, dismissed: 2);
    final repo = DriftNotificationRepository(db: db);

    expect((await repo.getAllUndismissed()).length, 1);
    expect(await repo.countAllUnread(), 0);

    await db.close();
  });

  test('notifications arriving after the upgrade are unread', () async {
    final db = openUpgradedFromV3(existingRows: 2);
    final repo = DriftNotificationRepository(db: db);
    expect(await repo.countAllUnread(), 0);

    await repo.insert(DeviceNotification(
      deviceId: 'dev1',
      type: NotificationType.leak,
      temperature: 55,
      timestamp: DateTime.now().toUtc(),
    ));

    expect(await repo.countAllUnread(), 1);

    await db.close();
  });

  test('a fresh install is unaffected', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final repo = DriftNotificationRepository(db: db);

    expect(await repo.countAllUnread(), 0);
    await repo.insert(DeviceNotification(
      deviceId: 'dev1',
      type: NotificationType.leak,
      temperature: 55,
      timestamp: DateTime.now().toUtc(),
    ));
    expect(await repo.countAllUnread(), 1);

    await db.close();
  });
}
