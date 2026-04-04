import 'package:get_it/get_it.dart';

import '../data/firebase/config/geyser_config_repository.dart';
import '../data/local/prefs_manager.dart';
import '../data/provisioning/ble_provisioning_repository.dart';
import '../domain/auth/repositories/auth_repository.dart';
import '../domain/ble/repositories/ble_repository.dart';
import '../domain/geyser/repositories/geyser_control_repository.dart';
import '../domain/geyser/repositories/rtdb_repository.dart';
import '../domain/notifications/repositories/notification_repository.dart';
import '../domain/telemetry/repositories/telemetry_repository.dart';
import '../presentation/auth/auth_gate/auth_gate_cubit.dart';
import '../presentation/auth/login/login_bloc.dart';
import '../presentation/auth/sign_up/sign_up_bloc.dart';
import '../presentation/ble/ble_connection_cubit.dart';
import '../presentation/geyser/geyser_control_cubit.dart';
import '../presentation/notifications/notification_service.dart';
import '../presentation/provisioning/provisioning_cubit.dart';
import '../presentation/stats/device_stats_cubit.dart';

void registerPresentation(GetIt getIt) {
  getIt.registerFactory<AuthGateCubit>(() => AuthGateCubit());
  getIt.registerFactory<LoginBloc>(() => LoginBloc());
  getIt.registerFactory<SignUpBloc>(() => SignUpBloc());

  // BLE — singleton because the connection lives across screens
  getIt.registerLazySingleton<BleConnectionCubit>(
    () => BleConnectionCubit(
      bleRepository: getIt<BleRepository>(),
      prefsManager: getIt<PrefsManager>(),
    ),
  );

  // Geyser control — singleton, listens to BLE status + streams.
  // The RTDB repository enables remote mode when BLE is disconnected.
  getIt.registerLazySingleton<GeyserControlCubit>(
    () => GeyserControlCubit(
      geyserControlRepository: getIt<GeyserControlRepository>(),
      bleRepository: getIt<BleRepository>(),
      rtdbRepository: getIt<RtdbRepository>(),
    ),
  );

  // Provisioning — factory (each session creates a fresh cubit)
  getIt.registerFactory<ProvisioningCubit>(
    () => ProvisioningCubit(
      provisioningRepository: getIt<BleProvisioningRepository>(),
      authRepository: getIt<AuthRepository>(),
      bleRepository: getIt<BleRepository>(),
    ),
  );

  // Device stats — singleton, streams daily stats + user config
  getIt.registerLazySingleton<DeviceStatsCubit>(
    () => DeviceStatsCubit(
      rtdbRepository: getIt<RtdbRepository>(),
      configRepository: getIt<GeyserConfigRepository>(),
      deviceId: 'g1',
    ),
  );

  // Notification service — singleton, manages BLE event subscriptions
  getIt.registerLazySingleton<NotificationService>(
    () => NotificationService(
      bleRepository: getIt<BleRepository>(),
      notificationRepository: getIt<NotificationRepository>(),
      telemetryRepository: getIt<TelemetryRepository>(),
      prefsManager: getIt<PrefsManager>(),
    ),
  );
}
