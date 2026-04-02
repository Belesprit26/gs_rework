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
  BoolColumn get dismissed =>
      boolean().withDefault(const Constant(false))();

  /// Whether this record has been pushed to cloud storage.
  BoolColumn get synced =>
      boolean().withDefault(const Constant(false))();

  /// Delivery source: 'ble' or 'remote'.
  TextColumn get source =>
      text().withDefault(const Constant('ble'))();
}
