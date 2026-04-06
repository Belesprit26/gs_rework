import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/debug/debug_log.dart';
import '../../domain/telemetry/repositories/telemetry_sync_repository.dart';
import '../local/prefs_manager.dart';

/// Orchestrates the telemetry + notification sync lifecycle:
///
/// 1. Called by workmanager at midnight → attempts sync on any connection.
/// 2. If the midnight push fails → sets a "pending retry" flag.
/// 3. Listens to connectivity changes → retries on first WiFi connection.
/// 4. On success → clears the retry flag.
///
/// This class is designed to be called from both:
/// - A running app (via DI singleton)
/// - A workmanager background isolate (via static [executeBackgroundSync])
class SyncOrchestrator {
  SyncOrchestrator({
    required TelemetrySyncRepository syncRepository,
    required PrefsManager prefsManager,
    Connectivity? connectivity,
  })  : _sync = syncRepository,
        _prefs = prefsManager,
        _connectivity = connectivity ?? Connectivity();

  final TelemetrySyncRepository _sync;
  final PrefsManager _prefs;
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // ── Public API ────────────────────────────────────────────────────

  /// Start listening for connectivity changes to handle WiFi retries.
  /// Call once from main.dart after DI setup.
  void startMonitoring() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    // Check if there's a pending retry from a previous failed midnight push.
    _checkPendingRetry();
  }

  /// Stop monitoring connectivity.
  Future<void> stopMonitoring() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Execute the sync. Called by workmanager at midnight or manually.
  ///
  /// Returns true if sync succeeded, false if it needs WiFi retry.
  Future<bool> attemptSync() async {
    try {
      final hasPending = await _sync.hasPendingRecords;
      if (!hasPending) {
        debugLog('SyncOrchestrator', 'No pending records');
        return true;
      }

      final count = await _sync.syncUnsyncedRecords();

      // Record success.
      await _prefs.setLastSyncTime(DateTime.now().toUtc());
      await _prefs.setPendingRetry(false);

      debugLog('SyncOrchestrator', 'Synced $count records');

      return true;
    } catch (e) {
      debugLog('SyncOrchestrator', 'Sync failed: $e — will retry on WiFi');

      // Mark for WiFi retry.
      await _prefs.setPendingRetry(true);

      return false;
    }
  }

  /// Static entry point for workmanager background isolate.
  ///
  /// Because workmanager runs in a separate isolate, we can't use
  /// the DI singleton. This method creates its own instances.
  /// Called from the workmanager callback dispatcher.
  static Future<bool> executeBackgroundSync({
    required TelemetrySyncRepository syncRepository,
    required PrefsManager prefsManager,
  }) async {
    try {
      final hasPending = await syncRepository.hasPendingRecords;
      if (!hasPending) return true;

      await syncRepository.syncUnsyncedRecords();

      await prefsManager.setLastSyncTime(DateTime.now().toUtc());
      await prefsManager.setPendingRetry(false);

      return true;
    } catch (e) {
      debugLog('SyncOrchestrator:bg', 'Sync failed: $e');

      await prefsManager.setPendingRetry(true);

      return false;
    }
  }

  // ── Private ───────────────────────────────────────────────────────

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final hasWifi = results.contains(ConnectivityResult.wifi);
    if (!hasWifi) return;

    if (!_prefs.hasPendingRetry) return;

    debugLog('SyncOrchestrator', 'WiFi detected — retrying sync');

    await attemptSync();
  }

  Future<void> _checkPendingRetry() async {
    if (!_prefs.hasPendingRetry) return;

    // Check current connectivity.
    final results = await _connectivity.checkConnectivity();
    final hasConnection = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
    );

    if (hasConnection) {
      debugLog('SyncOrchestrator', 'Found pending retry — attempting now');
      await attemptSync();
    }
  }
}
