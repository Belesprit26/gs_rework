import 'package:drift/drift.dart';

/// Drift table definition for device notification events.
///
/// Maps 1:1 to [DeviceNotification] in the domain layer.
class NotificationEntries extends Table {
  /// Auto-increment primary key.
  IntColumn get id => integer().autoIncrement()();

  /// BLE device ID this event came from.
  TextColumn get deviceId => text()();

  /// Event type code (matches [NotificationType.code]).
  IntColumn get type => integer()();

  /// Temperature in integer °C at the time of event.
  IntColumn get temperature => integer()();

  /// UTC timestamp of when the event occurred.
  DateTimeColumn get timestamp => dateTime()();

  /// Whether the user has dismissed this notification from the UI.
  ///
  /// Distinct from [read]: dismissing removes a row from the list,
  /// reading only means the user has seen it. The bell badge counts
  /// unread-and-undismissed, so neither action alone leaves a count
  /// stranded with nothing on screen to clear it.
  BoolColumn get dismissed =>
      boolean().withDefault(const Constant(false))();

  /// Whether the user has seen this notification in the list.
  ///
  /// Backfills to `true` for pre-existing rows in the v4 migration:
  /// they predate the concept, and defaulting them unread would spike
  /// the badge on upgrade with events the user has long since handled.
  BoolColumn get read =>
      boolean().withDefault(const Constant(false))();

  /// Whether this record has been pushed to cloud storage.
  BoolColumn get synced =>
      boolean().withDefault(const Constant(false))();

  /// Delivery source: 'ble' or 'remote'.
  TextColumn get source =>
      text().withDefault(const Constant('ble'))();
}
