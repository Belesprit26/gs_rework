import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/notification_entries.dart';
import 'tables/telemetry_entries.dart';

part 'app_database.g.dart';

/// The single Drift database for the app.
///
/// Tables:
/// - [TelemetryEntries] — periodic geyser telemetry readings.
/// - [NotificationEntries] — device notification events.
@DriftDatabase(tables: [TelemetryEntries, NotificationEntries])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// For testing: inject a custom query executor.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(notificationEntries);
          }
          if (from < 3) {
            await m.addColumn(notificationEntries, notificationEntries.source);
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'gs_rework.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
