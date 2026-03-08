import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/utils/version_check.dart';
import '../../../di/locator.dart';
import '../../../domain/auth/auth_gate/auth_gate_context.dart';
import '../../../domain/auth/auth_gate/auth_gate_decision.dart';
import '../../../domain/auth/auth_gate/auth_gate_policy.dart';
import '../../../domain/auth/entities/auth_user.dart';
import '../../../domain/auth/repositories/auth_repository.dart';
import '../../../domain/remote_config/repositories/remote_config_repository.dart';

part 'auth_gate_state.dart';

class AuthGateCubit extends Cubit<AuthGateState> {
  AuthGateCubit({
    AuthRepository? authRepository,
    AuthGatePolicy? authGatePolicy,
    RemoteConfigRepository? remoteConfigRepository,
  })  : _authRepository = authRepository ?? getIt<AuthRepository>(),
        _authGatePolicy = authGatePolicy ?? getIt<AuthGatePolicy>(),
        _remoteConfig = remoteConfigRepository ?? getIt<RemoteConfigRepository>(),
        super(const AuthGateState.loading()) {
    _sub = _authRepository.authStateChanges().listen(_onAuthStateChanged);
  }

  final AuthRepository _authRepository;
  final AuthGatePolicy _authGatePolicy;
  final RemoteConfigRepository _remoteConfig;
  late final StreamSubscription<AuthUser?> _sub;

  Future<void> _onAuthStateChanged(AuthUser? user) async {
    // Remote config flags
    final isMaintenance = _remoteConfig.isMaintenanceMode;
    final minVersion = _remoteConfig.minSupportedVersion;

    // Get current app version for comparison
    String currentVersion = '1.0.0';
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = info.version;
    } catch (_) {
      // Default to 1.0.0 if PackageInfo fails.
    }
    final versionOk = isVersionSupported(currentVersion, minVersion);

    if (user == null) {
      final ctx = AuthGateContext(
        user: null,
        isMaintenanceMode: isMaintenance,
        isMinVersionSupported: versionOk,
      );
      emit(AuthGateState.ready(
        user: null,
        decision: _authGatePolicy.decide(ctx),
      ));
      return;
    }

    // Check profile completeness
    final profileComplete = await _authRepository.isProfileComplete(user.uid);

    final ctx = AuthGateContext(
      user: user,
      isProfileComplete: profileComplete,
      isMaintenanceMode: isMaintenance,
      isMinVersionSupported: versionOk,
    );

    emit(AuthGateState.ready(
      user: user,
      decision: _authGatePolicy.decide(ctx),
    ));
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
