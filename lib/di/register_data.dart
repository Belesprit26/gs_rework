import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get_it/get_it.dart';

import '../data/ble/ble_owner_auth.dart';
import '../data/ble/flutter_blue_plus_ble_repository.dart';
import '../data/ble/mock_ble_repository.dart';
import '../data/firebase/auth/firebase_auth_repository.dart';
import '../data/firebase/config/geyser_config_repository.dart';
import '../data/firebase/fcm/push_notification_manager.dart';
import '../data/firebase/remote_config/firebase_remote_config_repository.dart';
import '../data/firebase/rtdb/firebase_rtdb_repository.dart';
import '../data/geyser/ble_geyser_control_repository.dart';
import '../data/local/app_database.dart';
import '../data/local/drift_notification_repository.dart';
import '../data/local/drift_telemetry_repository.dart';
import '../data/local/prefs_manager.dart';
import '../data/provisioning/ble_provisioning_repository.dart';
import '../data/sync/cloud_storage_sync_repository.dart';
import '../data/sync/sync_orchestrator.dart';
import '../data/telemetry/telemetry_recorder.dart';
import '../domain/auth/repositories/auth_repository.dart';
import '../domain/ble/repositories/ble_repository.dart';
import '../domain/geyser/repositories/geyser_control_repository.dart';
import '../domain/geyser/repositories/rtdb_repository.dart';
import '../domain/notifications/repositories/notification_repository.dart';
import '../domain/remote_config/repositories/remote_config_repository.dart';
import '../domain/telemetry/repositories/telemetry_repository.dart';
import '../domain/telemetry/repositories/telemetry_sync_repository.dart';
import '../presentation/notifications/notification_service.dart';

/// Set to true to use the mock BLE repo (no hardware needed).
const bool _useMockBle = false;

Future<void> registerData(GetIt getIt) async {
  // ── SharedPreferences manager ─────────────────────────────────
  final prefsManager = await PrefsManager.create();
  getIt.registerSingleton<PrefsManager>(prefsManager);

  // Firebase clients
  getIt.registerLazySingleton<FirebaseAuth>(() => FirebaseAuth.instance);
  getIt.registerLazySingleton<FirebaseFirestore>(
      () => FirebaseFirestore.instance);
  getIt.registerLazySingleton<FirebaseDatabase>(
      () => FirebaseDatabase.instance);
  getIt.registerLazySingleton<FirebaseRemoteConfig>(
      () => FirebaseRemoteConfig.instance);

  // Repositories
  getIt.registerLazySingleton<AuthRepository>(
    () => FirebaseAuthRepository(
      auth: getIt<FirebaseAuth>(),
      firestore: getIt<FirebaseFirestore>(),
    ),
  );

  final remoteConfigRepo = FirebaseRemoteConfigRepository(
    remoteConfig: getIt<FirebaseRemoteConfig>(),
  );
  await remoteConfigRepo.initialize();
  getIt.registerLazySingleton<RemoteConfigRepository>(() => remoteConfigRepo);

  // Geyser config (Firestore — syncs across devices)
  getIt.registerLazySingleton<GeyserConfigRepository>(
    () => GeyserConfigRepository(
      auth: getIt<FirebaseAuth>(),
      firestore: getIt<FirebaseFirestore>(),
    ),
  );

  // BLE
  getIt.registerLazySingleton<BleRepository>(
    () => _useMockBle ? MockBleRepository() : FlutterBluePlusBleRepository(),
  );

  // BLE owner-lock — challenge-response unlock + key distribution
  // through the account's Firestore scope.
  getIt.registerLazySingleton<BleOwnerAuth>(
    () => BleOwnerAuth(
      bleRepository: getIt<BleRepository>(),
      auth: getIt<FirebaseAuth>(),
      firestore: getIt<FirebaseFirestore>(),
      prefsManager: getIt<PrefsManager>(),
    ),
  );

  // Provisioning
  getIt.registerFactory<BleProvisioningRepository>(
    () => BleProvisioningRepository(bleRepository: getIt<BleRepository>()),
  );

  // Geyser control (BLE — local mode)
  getIt.registerLazySingleton<GeyserControlRepository>(
    () => BleGeyserControlRepository(bleRepository: getIt<BleRepository>()),
  );

  // RTDB repository (remote mode)
  getIt.registerLazySingleton<RtdbRepository>(
    () => FirebaseRtdbRepository(
      auth: getIt<FirebaseAuth>(),
      database: getIt<FirebaseDatabase>(),
    ),
  );

  // Local database
  getIt.registerLazySingleton<AppDatabase>(() => AppDatabase());

  // Telemetry
  getIt.registerLazySingleton<TelemetryRepository>(
    () => DriftTelemetryRepository(db: getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<TelemetryRecorder>(
    () => TelemetryRecorder(
      telemetryRepository: getIt<TelemetryRepository>(),
      geyserControlRepository: getIt<GeyserControlRepository>(),
      bleRepository: getIt<BleRepository>(),
      prefsManager: getIt<PrefsManager>(),
    ),
  );

  // Notifications
  getIt.registerLazySingleton<NotificationRepository>(
    () => DriftNotificationRepository(db: getIt<AppDatabase>()),
  );

  // ── Sync (Phase 4) ─────────────────────────────────────────────

  getIt.registerLazySingleton<FirebaseStorage>(
    () => FirebaseStorage.instance,
  );

  getIt.registerLazySingleton<TelemetrySyncRepository>(
    () => CloudStorageSyncRepository(
      storage: getIt<FirebaseStorage>(),
      auth: getIt<FirebaseAuth>(),
      telemetryRepository: getIt<TelemetryRepository>(),
      notificationRepository: getIt<NotificationRepository>(),
    ),
  );

  getIt.registerLazySingleton<SyncOrchestrator>(
    () => SyncOrchestrator(
      syncRepository: getIt<TelemetrySyncRepository>(),
      prefsManager: getIt<PrefsManager>(),
    ),
  );

  // ── FCM push notifications ────────────────────────────────────

  getIt.registerLazySingleton<FirebaseMessaging>(
    () => FirebaseMessaging.instance,
  );

  getIt.registerLazySingleton<PushNotificationManager>(
    () => PushNotificationManager(
      messaging: getIt<FirebaseMessaging>(),
      functions: FirebaseFunctions.instance,
      notificationRepository: getIt<NotificationRepository>(),
      prefsManager: getIt<PrefsManager>(),
      notificationService: getIt<NotificationService>(),
    ),
  );
}
