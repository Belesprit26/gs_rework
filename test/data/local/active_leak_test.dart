import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/data/local/app_database.dart';
import 'package:gs_rework/data/local/drift_notification_repository.dart';
import 'package:gs_rework/domain/notifications/entities/device_notification.dart';

/// Locks the app-side leak-latch derivation: a leak is "active" when a
/// device's most recent [NotificationType.leak] is not yet followed by a
/// [NotificationType.leakClear]. This mirrors the firmware latch and drives
/// the dashboard's hanging drop badge + gated toggle.
void main() {
  late AppDatabase db;
  late DriftNotificationRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = DriftNotificationRepository(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  DeviceNotification event(
    NotificationType type, {
    String deviceId = 'dev1',
    required int minutesAgo,
  }) {
    return DeviceNotification(
      deviceId: deviceId,
      type: type,
      temperature: 55,
      timestamp:
          DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo)),
    );
  }

  test('no events → not active', () async {
    expect(await repo.hasActiveLeak('dev1'), isFalse);
  });

  test('leak with no clear → active', () async {
    await repo.insert(event(NotificationType.leak, minutesAgo: 5));
    expect(await repo.hasActiveLeak('dev1'), isTrue);
  });

  test('leak then a later clear → not active', () async {
    await repo.insert(event(NotificationType.leak, minutesAgo: 10));
    await repo.insert(event(NotificationType.leakClear, minutesAgo: 2));
    expect(await repo.hasActiveLeak('dev1'), isFalse);
  });

  test('cleared, then a fresh leak → active again', () async {
    await repo.insert(event(NotificationType.leak, minutesAgo: 30));
    await repo.insert(event(NotificationType.leakClear, minutesAgo: 20));
    await repo.insert(event(NotificationType.leak, minutesAgo: 1));
    expect(await repo.hasActiveLeak('dev1'), isTrue);
  });

  test('an older clear does not resolve a newer leak', () async {
    // Out-of-order arrival: the clear is older than the current leak.
    await repo.insert(event(NotificationType.leakClear, minutesAgo: 15));
    await repo.insert(event(NotificationType.leak, minutesAgo: 5));
    expect(await repo.hasActiveLeak('dev1'), isTrue);
  });

  test('leak state is per-device', () async {
    await repo.insert(
        event(NotificationType.leak, deviceId: 'dev1', minutesAgo: 5));
    expect(await repo.hasActiveLeak('dev1'), isTrue);
    expect(await repo.hasActiveLeak('dev2'), isFalse);
  });

  test('dismissal does not clear the hazard', () async {
    // hasActiveLeak reads the raw event history, independent of the UI's
    // dismissed flag — clearing the list must not clear the latch.
    await repo.insert(DeviceNotification(
      deviceId: 'dev1',
      type: NotificationType.leak,
      temperature: 55,
      timestamp: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      dismissed: true,
    ));
    expect(await repo.hasActiveLeak('dev1'), isTrue);
  });
}
