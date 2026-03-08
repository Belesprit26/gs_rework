import '../entities/telemetry_record.dart';

/// Domain contract for telemetry local storage.
///
/// Stores readings from BLE in SQLite for up to 7 days.
/// Records are marked as `synced` after successful Firebase push (Phase 4).
abstract class TelemetryRepository {
  // ── Write ─────────────────────────────────────────────────────────

  /// Insert a new telemetry reading.
  Future<void> insert(TelemetryRecord record);

  /// Insert many records in a single transaction (e.g. from bulk BLE transfer).
  Future<void> insertBatch(List<TelemetryRecord> records);

  // ── Read ──────────────────────────────────────────────────────────

  /// Get all records for a device, ordered by timestamp descending.
  Future<List<TelemetryRecord>> getRecords(String deviceId, {int? limit});

  /// Get all un-synced records (for Firebase push).
  Future<List<TelemetryRecord>> getUnsyncedRecords({int? limit});

  /// Get the most recent record for a device.
  Future<TelemetryRecord?> getLatest(String deviceId);

  /// Count total records in the database.
  Future<int> count();

  // ── Sync support (Phase 4) ────────────────────────────────────────

  /// Mark a batch of records as synced by their IDs.
  Future<void> markSynced(List<int> ids);

  // ── Maintenance ───────────────────────────────────────────────────

  /// Delete records older than [retentionDays] (default 7).
  Future<int> pruneOlderThan({int retentionDays = 7});

  /// Delete all records (for testing / reset).
  Future<void> deleteAll();
}
