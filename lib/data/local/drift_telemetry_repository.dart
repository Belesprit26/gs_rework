import 'package:drift/drift.dart';

import '../../domain/telemetry/entities/telemetry_record.dart';
import '../../domain/telemetry/repositories/telemetry_repository.dart';
import 'app_database.dart';

/// Drift/SQLite implementation of [TelemetryRepository].
///
/// All queries go through the generated [AppDatabase] + [TelemetryEntries] table.
class DriftTelemetryRepository implements TelemetryRepository {
  DriftTelemetryRepository({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  // ── Write ─────────────────────────────────────────────────────────

  @override
  Future<void> insert(TelemetryRecord record) async {
    await _db.into(_db.telemetryEntries).insert(
          _toCompanion(record),
        );
  }

  @override
  Future<void> insertBatch(List<TelemetryRecord> records) async {
    await _db.batch((batch) {
      batch.insertAll(
        _db.telemetryEntries,
        records.map(_toCompanion).toList(),
      );
    });
  }

  // ── Read ──────────────────────────────────────────────────────────

  @override
  Future<List<TelemetryRecord>> getRecords(String deviceId, {int? limit}) async {
    final query = _db.select(_db.telemetryEntries)
      ..where((t) => t.deviceId.equals(deviceId))
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);

    if (limit != null) {
      query.limit(limit);
    }

    final rows = await query.get();
    return rows.map(_fromEntry).toList();
  }

  @override
  Future<List<TelemetryRecord>> getUnsyncedRecords({int? limit}) async {
    final query = _db.select(_db.telemetryEntries)
      ..where((t) => t.synced.equals(false))
      ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]);

    if (limit != null) {
      query.limit(limit);
    }

    final rows = await query.get();
    return rows.map(_fromEntry).toList();
  }

  @override
  Future<TelemetryRecord?> getLatest(String deviceId) async {
    final query = _db.select(_db.telemetryEntries)
      ..where((t) => t.deviceId.equals(deviceId))
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
      ..limit(1);

    final rows = await query.get();
    return rows.isEmpty ? null : _fromEntry(rows.first);
  }

  @override
  Future<int> count() async {
    final countExpr = _db.telemetryEntries.id.count();
    final query = _db.selectOnly(_db.telemetryEntries)..addColumns([countExpr]);
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  // ── Sync support ──────────────────────────────────────────────────

  @override
  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await (_db.update(_db.telemetryEntries)
          ..where((t) => t.id.isIn(ids)))
        .write(const TelemetryEntriesCompanion(synced: Value(true)));
  }

  // ── Maintenance ───────────────────────────────────────────────────

  @override
  Future<int> pruneOlderThan({
    int retentionDays = 7,
    bool onlySynced = true,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(Duration(days: retentionDays));
    final query = _db.delete(_db.telemetryEntries)
      ..where((t) => t.timestamp.isSmallerThanValue(cutoff));
    if (onlySynced) {
      query.where((t) => t.synced.equals(true));
    }
    return await query.go();
  }

  @override
  Future<void> deleteAll() async {
    await _db.delete(_db.telemetryEntries).go();
  }

  // ── Private: mapping ──────────────────────────────────────────────

  static TelemetryEntriesCompanion _toCompanion(TelemetryRecord record) {
    return TelemetryEntriesCompanion.insert(
      deviceId: record.deviceId,
      timestamp: record.timestamp,
      temperature: record.temperature,
      isOn: Value(record.isOn),
      minTemp: Value(record.minTemp),
      maxTemp: Value(record.maxTemp),
      synced: Value(record.synced),
    );
  }

  static TelemetryRecord _fromEntry(TelemetryEntry entry) {
    return TelemetryRecord(
      id: entry.id,
      deviceId: entry.deviceId,
      timestamp: entry.timestamp,
      temperature: entry.temperature,
      isOn: entry.isOn,
      minTemp: entry.minTemp,
      maxTemp: entry.maxTemp,
      synced: entry.synced,
    );
  }
}
