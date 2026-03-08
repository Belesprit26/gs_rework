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

  /// Undismissed notifications filtered to [enabledTypes] only.
  /// If [enabledTypes] is null, returns all undismissed.
  Future<List<DeviceNotification>> getUndismissed(
    String deviceId, {
    Set<NotificationType>? enabledTypes,
  });

  /// Count undismissed notifications for badge, filtered to [enabledTypes].
  Future<int> countUndismissed(
    String deviceId, {
    Set<NotificationType>? enabledTypes,
  });

  /// Get unsynced notifications for cloud push.
  Future<List<DeviceNotification>> getUnsynced({int? limit});

  /// Mark a notification as dismissed (UI-only removal).
  Future<void> markDismissed(int id);

  /// Mark notifications as synced to cloud.
  Future<void> markSynced(List<int> ids);

  /// Delete notifications older than [retentionDays] days.
  Future<int> pruneOlderThan({int retentionDays = 7});

  /// Delete all notifications (for development/reset).
  Future<void> deleteAll();
}
