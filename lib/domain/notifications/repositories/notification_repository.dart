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

  /// All non-dismissed notifications across EVERY device, newest first.
  /// Alerts are pooled — you want to see a problem on any geyser
  /// regardless of which one you're currently viewing. Muting is a UI
  /// concern, so all types are returned.
  Future<List<DeviceNotification>> getAllUndismissed({int? limit});

  /// Pooled unread count across every device, for the app-bar badge,
  /// filtered to [enabledTypes].
  ///
  /// Counts rows that are neither read nor dismissed. Both conditions are
  /// needed: counting only unread would strand the badge above an empty
  /// list when a user dismisses without opening, and counting only
  /// undismissed is what made the badge unclearable — viewing the list
  /// left it untouched, so it only ever went down by swiping each row.
  Future<int> countAllUnread({Set<NotificationType>? enabledTypes});

  /// Mark every stored notification as read. Called when the user opens
  /// the notifications list — that is the act of seeing them.
  Future<void> markAllRead();

  /// Whether [deviceId] has an unresolved water leak: its most recent
  /// [NotificationType.leak] is not yet followed by a
  /// [NotificationType.leakClear]. Derived from the event pair so it
  /// survives app restarts and matches the firmware's latch. Independent
  /// of dismissal — clearing the notification list must not clear the
  /// hazard state.
  Future<bool> hasActiveLeak(String deviceId);

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
