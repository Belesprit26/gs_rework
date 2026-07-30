import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';

import 'core/debug/debug_log.dart';
import 'data/firebase/fcm/push_notification_manager.dart';
import 'data/local/prefs_manager.dart';
import 'data/sync/sync_orchestrator.dart';
import 'data/sync/workmanager_config.dart';
import 'data/telemetry/telemetry_recorder.dart';
import 'di/locator.dart';
import 'domain/notifications/repositories/notification_repository.dart';
import 'domain/telemetry/repositories/telemetry_repository.dart';
import 'presentation/geyser/geyser_control_cubit.dart';
import 'firebase_options.dart';
import 'presentation/app/app.dart';
import 'presentation/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Foundational — the app cannot run without Firebase and DI, so a
  // failure here is allowed to surface loudly.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Crashlytics — catch all Flutter framework errors and unhandled
  // async errors so they appear in the Firebase Console.
  FlutterError.onError =
      FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  await setupLocator();

  // Non-critical startup — each step is an enhancement (telemetry,
  // notifications, push, background sync). A failure in any one of
  // them must not prevent the app from launching; it is logged and
  // reported to Crashlytics instead.

  // Telemetry recorder — listens to BLE status and automatically
  // records when a device is connected.
  await _guardedStart('TelemetryRecorder',
      () => getIt<TelemetryRecorder>().start());

  // Notification service — reads buffered events on BLE connect and
  // subscribes to real-time event notifications.
  await _guardedStart('NotificationService',
      () => getIt<NotificationService>().start());

  // FCM push notifications — requests permission, registers the
  // token, and sets up foreground display.
  await _guardedStart('PushNotifications',
      () => getIt<PushNotificationManager>().initialize());

  // Sync orchestrator — monitors connectivity for WiFi retries when a
  // midnight push fails.
  await _guardedStart('SyncOrchestrator',
      () => getIt<SyncOrchestrator>().startMonitoring());

  // Workmanager daily task for midnight sync.
  await _guardedStart('Workmanager', initializeWorkmanager);

  // Sign-in reactivation: sign-out (dashboard_page) stops the
  // per-account services, and nothing else restarts them until app
  // relaunch. Only a signed-out → signed-in transition triggers this
  // (the initial auth event is skipped), so cold-start behavior is
  // unchanged; start() is idempotent regardless.
  User? lastAuthUser = FirebaseAuth.instance.currentUser;
  FirebaseAuth.instance.authStateChanges().listen((user) {
    final cameBack = user != null && lastAuthUser == null;
    lastAuthUser = user;
    if (!cameBack) return;
    getIt<TelemetryRecorder>().start();
    getIt<NotificationService>().start();
    unawaited(getIt<PushNotificationManager>().refreshRegistration());
    final prefs = getIt<PrefsManager>();
    final bleMac = prefs.pairedDeviceId;
    final rtdbId = bleMac != null ? prefs.getRtdbDeviceId(bleMac) : null;
    getIt<GeyserControlCubit>().reactivateAfterSignIn(deviceId: rtdbId);
  });

  // Foreground fallback: background tasks are best-effort (especially
  // iOS BGAppRefreshTask) — if the daily sync hasn't run in >26 h,
  // run it now. Fire-and-forget so app launch isn't delayed.
  unawaited(_guardedStart(
    'SyncFallback',
    () => runSyncFallbackIfOverdue(
      orchestrator: getIt<SyncOrchestrator>(),
      prefsManager: getIt<PrefsManager>(),
      telemetryRepository: getIt<TelemetryRepository>(),
      notificationRepository: getIt<NotificationRepository>(),
    ),
  ));

  runApp(const App());
}

/// Run one startup step, containing any error so launch continues.
Future<void> _guardedStart(String name, FutureOr<void> Function() start) async {
  try {
    await start();
  } catch (e, st) {
    debugLog('Startup', '$name failed to start: $e');
    // Non-fatal: the app still launches without this subsystem.
    unawaited(
      FirebaseCrashlytics.instance
          .recordError(e, st, reason: 'startup:$name', fatal: false),
    );
  }
}
