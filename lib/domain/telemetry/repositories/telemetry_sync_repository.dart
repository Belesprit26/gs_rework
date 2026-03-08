/// Domain contract for syncing telemetry data to remote storage.
///
/// Implementations handle the upload strategy (Cloud Storage, etc).
/// The orchestrator calls this after gathering unsynced records.
abstract class TelemetrySyncRepository {
  /// Push all unsynced local records to remote storage.
  ///
  /// Returns the number of records successfully synced.
  /// Throws on network/auth failure so the caller can retry.
  Future<int> syncUnsyncedRecords();

  /// Whether there are any records waiting to be synced.
  Future<bool> get hasPendingRecords;
}
