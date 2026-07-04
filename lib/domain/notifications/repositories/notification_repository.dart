import '../entities/device_notification.dart';

/// Domain contract for notification persistence.
///
/// All notifications are always stored regardless of user preferences.
/// Preferences control visibility (UI list, badge count) and alerting.
abstract class NotificationRepository {
  /// Insert a single notification.
  Future<void> insert(DeviceNotification notification);

  /// Insert multiple notifications (e.g. from buffered events on reconnect).
  Future<void> insertBatch(List<DeviceNotification> notifications);

  /// All notifications for a device, newest first.
  Future<List<DeviceNotification>> getAll(String deviceId, {int? limit});

  /// All non-dismissed notifications, newest first.
  /// Unlike the old version this returns ALL types (muting is a UI concern).
  Future<List<DeviceNotification>> getUndismissed(String deviceId);

  /// Count undismissed notifications for badge, filtered to [enabledTypes].
  Future<int> countUndismissed(
    String deviceId, {
    Set<NotificationType>? enabledTypes,
  });

  /// Check if a matching event already exists (for FCM dedup).
  /// Matches on [deviceId], [type], and timestamp within [window].
  Future<bool> hasMatchingEvent({
    required String deviceId,
    required NotificationType type,
    required DateTime timestamp,
    Duration window = const Duration(minutes: 2),
  });

  /// Get unsynced notifications for cloud push.
  Future<List<DeviceNotification>> getUnsynced({int? limit});

  /// Mark a notification as dismissed (UI-only removal).
  Future<void> markDismissed(int id);

  /// Mark notifications as synced to cloud.
  Future<void> markSynced(List<int> ids);

  /// Delete notifications older than [retentionDays] days.
  ///
  /// By default only **synced** notifications are deleted, so events
  /// that have not reached the cloud yet are never lost to retention.
  /// Pass [onlySynced] = false for the absolute backstop prune.
  Future<int> pruneOlderThan({int retentionDays = 7, bool onlySynced = true});

  /// Delete all notifications (for development/reset).
  Future<void> deleteAll();
}
