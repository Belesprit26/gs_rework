import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/firebase/fcm/push_notification_manager.dart';
import '../../di/locator.dart';
import '../auth/auth_gate/auth_gate_view.dart';
import '../ble/ble_connection_cubit.dart';
import '../device/device_registry_cubit.dart';
import '../geyser/geyser_control_cubit.dart';
import '../stats/device_stats_cubit.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<BleConnectionCubit>.value(
          value: getIt<BleConnectionCubit>(),
        ),
        BlocProvider<GeyserControlCubit>.value(
          value: getIt<GeyserControlCubit>(),
        ),
        BlocProvider<DeviceStatsCubit>.value(
          value: getIt<DeviceStatsCubit>(),
        ),
        BlocProvider<DeviceRegistryCubit>.value(
          value: getIt<DeviceRegistryCubit>(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: PushNotificationManager.navigatorKey,
        home: const AuthGateView(),
      ),
    );
  }
}
