import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/widgets.dart';

import 'data/firebase/fcm/push_notification_manager.dart';
import 'data/sync/sync_orchestrator.dart';
import 'data/sync/workmanager_config.dart';
import 'data/telemetry/telemetry_recorder.dart';
import 'di/locator.dart';
import 'firebase_options.dart';
import 'presentation/app/app.dart';
import 'presentation/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // Start the telemetry recorder — it listens to BLE status
  // and automatically records when a device is connected.
  getIt<TelemetryRecorder>().start();

  // Start the notification service — reads buffered events on
  // BLE connect and subscribes to real-time event notifications.
  getIt<NotificationService>().start();

  // Initialize FCM push notifications — requests permission,
  // registers the token, and sets up foreground display.
  await getIt<PushNotificationManager>().initialize();

  // Start the sync orchestrator — monitors connectivity for WiFi retries
  // when a midnight push fails.
  getIt<SyncOrchestrator>().startMonitoring();

  // Register the workmanager daily task for midnight sync.
  await initializeWorkmanager();

  runApp(const App());
}
