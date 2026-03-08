import 'package:drift/drift.dart';

/// Drift table definition for telemetry readings.
///
/// Maps 1:1 to [TelemetryRecord] in the domain layer.
/// Column naming follows SQLite conventions (snake_case).
class TelemetryEntries extends Table {
  /// Auto-increment primary key.
  IntColumn get id => integer().autoIncrement()();

  /// BLE device ID this reading came from.
  TextColumn get deviceId => text()();

  /// UTC timestamp of the reading.
  DateTimeColumn get timestamp => dateTime()();

  /// Water temperature in °C (stored as real).
  RealColumn get temperature => real()();

  /// Whether the geyser element was on (0 = off, 1 = on).
  BoolColumn get isOn => boolean().withDefault(const Constant(false))();

  /// Min temp limit at time of reading.
  IntColumn get minTemp => integer().withDefault(const Constant(30))();

  /// Max temp limit at time of reading.
  IntColumn get maxTemp => integer().withDefault(const Constant(60))();

  /// Whether this record has been pushed to Firebase.
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
}
