import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/debug/debug_log.dart';

import '../../domain/notifications/repositories/notification_repository.dart';
import '../../domain/telemetry/repositories/telemetry_repository.dart';
import '../../firebase_options.dart';
import '../local/app_database.dart';
import '../local/drift_notification_repository.dart';
import '../local/drift_telemetry_repository.dart';
import '../local/prefs_manager.dart';
import 'cloud_storage_sync_repository.dart';
import 'sync_orchestrator.dart';

/// Unique task name for the daily telemetry sync.
const String kDailySyncTaskName = 'gs_daily_telemetry_sync';

/// Unique task identifier.
const String kDailySyncTaskId = 'com.geyserswitch.dailySync';

/// Initialize workmanager and register the periodic sync task.
///
/// Call once from main.dart.
Future<void> initializeWorkmanager() async {
  await Workmanager().initialize(_callbackDispatcher);

  // Register a daily periodic task.
  // On Android this uses WorkManager's PeriodicWorkRequest.
  // On iOS it uses BGTaskScheduler.
  // `frequency` = minimum interval (OS may delay further).
  await Workmanager().registerPeriodicTask(
    kDailySyncTaskId,
    kDailySyncTaskName,
    frequency: const Duration(hours: 24),
    initialDelay: _durationUntilMidnight(),
    constraints: Constraints(
      networkType: NetworkType.connected, // Require any network
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: const Duration(minutes: 15),
  );

  debugLog('Workmanager',
      'Registered daily sync task, '
      'first run in ${_durationUntilMidnight().inMinutes} minutes');
}

/// Foreground fallback for the daily background sync.
///
/// iOS BGAppRefreshTask is best-effort — the OS may defer or never run
/// it — and Android WorkManager can be delayed by aggressive battery
/// management. Called on app start: if the last successful sync is
/// older than [threshold], run the same sync + prune sequence the
/// background task would have, inline.
Future<void> runSyncFallbackIfOverdue({
  required SyncOrchestrator orchestrator,
  required PrefsManager prefsManager,
  required TelemetryRepository telemetryRepository,
  required NotificationRepository notificationRepository,
  Duration threshold = const Duration(hours: 26),
}) async {
  await prefsManager.reload();
  final last = prefsManager.lastSyncTime;
  final parsed = last == null ? null : DateTime.tryParse(last);
  if (parsed != null &&
      DateTime.now().toUtc().difference(parsed) < threshold) {
    return;
  }

  debugLog('Workmanager', 'Background sync overdue — foreground fallback');
  await orchestrator.attemptSync();

  await telemetryRepository.pruneOlderThan(retentionDays: 7);
  await notificationRepository.pruneOlderThan(retentionDays: 7);
  await telemetryRepository.pruneOlderThan(retentionDays: 60, onlySynced: false);
  await notificationRepository.pruneOlderThan(
      retentionDays: 60, onlySynced: false);
}

/// Calculate delay until 23:55 local time (today or tomorrow).
Duration _durationUntilMidnight() {
  final now = DateTime.now();
  var target = DateTime(now.year, now.month, now.day, 23, 55);

  // If 23:55 has already passed today, schedule for tomorrow.
  if (target.isBefore(now)) {
    target = target.add(const Duration(days: 1));
  }

  return target.difference(now);
}

/// Top-level function — workmanager callback dispatcher.
///
/// Runs in a separate isolate. Must be a top-level or static function.
/// We set up minimal dependencies here (no full DI — just what's needed).
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Android delivers the task NAME; iOS (BGTaskScheduler) delivers
      // the task IDENTIFIER. Accept both.
      if (taskName != kDailySyncTaskName && taskName != kDailySyncTaskId) {
        return true;
      }

      // Initialize Firebase in the background isolate.
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Create minimal dependencies for sync.
      final db = AppDatabase();
      final telemetryRepo = DriftTelemetryRepository(db: db);
      final notificationRepo = DriftNotificationRepository(db: db);
      final prefsManager = await PrefsManager.create();

      final syncRepo = CloudStorageSyncRepository(
        storage: FirebaseStorage.instance,
        auth: FirebaseAuth.instance,
        telemetryRepository: telemetryRepo,
        notificationRepository: notificationRepo,
      );

      final success = await SyncOrchestrator.executeBackgroundSync(
        syncRepository: syncRepo,
        prefsManager: prefsManager,
      );

      // Prune AFTER syncing, and only records that made it to the
      // cloud — unsynced data must never be lost to retention.
      await telemetryRepo.pruneOlderThan(retentionDays: 7);
      await notificationRepo.pruneOlderThan(retentionDays: 7);

      // Absolute backstop: bound local growth even if sync is
      // permanently broken (e.g. account signed out for months).
      await telemetryRepo.pruneOlderThan(retentionDays: 60, onlySynced: false);
      await notificationRepo.pruneOlderThan(
          retentionDays: 60, onlySynced: false);

      // Close the database.
      await db.close();

      debugLog('Workmanager',
          'Daily sync ${success ? 'succeeded' : 'needs retry'}');

      return success;
    } catch (e) {
      debugLog('Workmanager', 'Task failed: $e');
      return false; // Workmanager will retry with backoff.
    }
  });
}
