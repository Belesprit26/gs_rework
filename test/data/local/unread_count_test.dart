import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/data/local/app_database.dart';
import 'package:gs_rework/data/local/drift_notification_repository.dart';
import 'package:gs_rework/domain/notifications/entities/device_notification.dart';

/// Locks the bell-badge semantics: the count is *unread and undismissed*.
///
/// Field-tested 2026-08-13: the badge counted undismissed only, so reading
/// the list never cleared it — the number could only be reduced by swiping
/// away every row one at a time. Reading and clearing are separate acts and
/// the count has to respect both, or it strands.
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
    int minutesAgo = 1,
  }) {
    return DeviceNotification(
      deviceId: deviceId,
      type: type,
      temperature: 55,
      timestamp:
          DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo)),
    );
  }

  test('no notifications → zero', () async {
    expect(await repo.countAllUnread(), 0);
  });

  test('a new notification is unread', () async {
    await repo.insert(event(NotificationType.leak));
    expect(await repo.countAllUnread(), 1);
  });

  test('markAllRead clears the count — the bug this fixes', () async {
    await repo.insert(event(NotificationType.leak));
    await repo.insert(event(NotificationType.maxTempOff));
    expect(await repo.countAllUnread(), 2);

    await repo.markAllRead();

    expect(await repo.countAllUnread(), 0);
  });

  test('read notifications stay in the list', () async {
    await repo.insert(event(NotificationType.leak));
    await repo.markAllRead();

    // Reading is not dismissing: the row is still there to look at.
    expect((await repo.getAllUndismissed()).length, 1);
    expect(await repo.countAllUnread(), 0);
  });

  test('dismissing an unread notification does not strand the badge',
      () async {
    await repo.insert(event(NotificationType.leak));
    final row = (await repo.getAllUndismissed()).single;

    await repo.markDismissed(row.id!);

    // Counting unread alone would still say 1 here, with an empty list
    // and no way left to clear it.
    expect(await repo.countAllUnread(), 0);
    expect(await repo.getAllUndismissed(), isEmpty);
  });

  test('notifications arriving after a read are counted again', () async {
    await repo.insert(event(NotificationType.leak));
    await repo.markAllRead();
    expect(await repo.countAllUnread(), 0);

    await repo.insert(event(NotificationType.maxOnTimeout));

    expect(await repo.countAllUnread(), 1);
  });

  test('the enabledTypes filter still applies', () async {
    await repo.insert(event(NotificationType.leak));
    await repo.insert(event(NotificationType.maxTempOff));

    final count = await repo.countAllUnread(
      enabledTypes: {NotificationType.leak},
    );

    expect(count, 1);
  });

  test('counts are pooled across devices', () async {
    await repo.insert(event(NotificationType.leak, deviceId: 'dev1'));
    await repo.insert(event(NotificationType.leak, deviceId: 'dev2'));

    expect(await repo.countAllUnread(), 2);
  });

  test('markAllRead is pooled and idempotent', () async {
    await repo.insert(event(NotificationType.leak, deviceId: 'dev1'));
    await repo.insert(event(NotificationType.leak, deviceId: 'dev2'));

    await repo.markAllRead();
    await repo.markAllRead();

    expect(await repo.countAllUnread(), 0);
  });
}
