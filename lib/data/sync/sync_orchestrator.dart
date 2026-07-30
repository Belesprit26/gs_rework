import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import '../../core/debug/debug_log.dart';
import '../../domain/telemetry/repositories/telemetry_sync_repository.dart';
import '../local/prefs_manager.dart';
import 'sync_lock.dart';

/// Orchestrates the telemetry + notification sync lifecycle:
///
/// 1. Called by workmanager at midnight → attempts sync on any connection.
/// 2. If the midnight push fails → sets a "pending retry" flag.
/// 3. Listens to connectivity changes → retries on first WiFi connection.
/// 4. On success → clears the retry flag.
///
/// All entry points (main isolate and the workmanager background
/// isolate) serialize through a cross-isolate [SyncLock], so at most
/// one sync runs at a time. If the lock is held, the attempt is simply
/// skipped — the holder is already doing the work.
///
/// This class is designed to be called from both:
/// - A running app (via DI singleton)
/// - A workmanager background isolate (via static [executeBackgroundSync])
class SyncOrchestrator {
  SyncOrchestrator({
    required TelemetrySyncRepository syncRepository,
    required PrefsManager prefsManager,
    Connectivity? connectivity,
    SyncLock? syncLock,
  })  : _sync = syncRepository,
        _prefs = prefsManager,
        _connectivity = connectivity ?? Connectivity(),
        _lock = syncLock;

  final TelemetrySyncRepository _sync;
  final PrefsManager _prefs;
  final Connectivity _connectivity;
  SyncLock? _lock;

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
  /// Returns true if sync succeeded (or was skipped because another
  /// sync already holds the lock), false if it needs WiFi retry.
  Future<bool> attemptSync() async {
    final lock = _lock ??= await SyncLock.inDocumentsDir();
    if (!await lock.tryAcquire()) {
      debugLog('SyncOrchestrator', 'Sync already running — skipped');
      return true;
    }
    try {
      return await _runSync(_sync, _prefs);
    } finally {
      await lock.release();
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
    final lock = await SyncLock.inDocumentsDir();
    if (!await lock.tryAcquire()) {
      debugLog('SyncOrchestrator:bg', 'Sync already running — skipped');
      return true;
    }
    try {
      return await _runSync(syncRepository, prefsManager, tag: ':bg');
    } finally {
      await lock.release();
    }
  }

  // ── Private ───────────────────────────────────────────────────────

  /// The actual sync body, shared by both entry points. Assumes the
  /// caller holds the [SyncLock].
  static Future<bool> _runSync(
    TelemetrySyncRepository sync,
    PrefsManager prefs, {
    String tag = '',
  }) async {
    try {
      final hasPending = await sync.hasPendingRecords;
      if (!hasPending) {
        debugLog('SyncOrchestrator$tag', 'No pending records');
        // Still a successful pass — stamp it so the foreground
        // fallback doesn't re-run on every launch.
        await prefs.setLastSyncTime(DateTime.now().toUtc());
        return true;
      }

      final count = await sync.syncUnsyncedRecords();

      // Record success.
      await prefs.setLastSyncTime(DateTime.now().toUtc());
      await prefs.setPendingRetry(false);

      debugLog('SyncOrchestrator$tag', 'Synced $count records');

      return true;
    } catch (e) {
      debugLog('SyncOrchestrator$tag', 'Sync failed: $e — will retry on WiFi');

      // Mark for WiFi retry. Partial progress is already durable:
      // uploaded chunks stay uploaded and their records stay marked
      // synced, so the retry only re-attempts what actually failed.
      await prefs.setPendingRetry(true);

      return false;
    }
  }

  Future<void> _onConnectivityChanged(List<ConnectivityResult> results) async {
    final hasWifi = results.contains(ConnectivityResult.wifi);
    if (!hasWifi) return;

    // The background isolate writes the retry flag through its own
    // SharedPreferences instance; reload so this isolate's cache
    // doesn't miss it.
    await _prefs.reload();
    if (!_prefs.hasPendingRetry) return;

    debugLog('SyncOrchestrator', 'WiFi detected — retrying sync');

    await attemptSync();
  }

  Future<void> _checkPendingRetry() async {
    await _prefs.reload();
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
