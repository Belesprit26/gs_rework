import 'package:get_it/get_it.dart';

import '../domain/auth/auth_gate/auth_gate_policy.dart';
import '../domain/auth/repositories/auth_repository.dart';
import '../domain/auth/usecases/forgot_password.dart';
import '../domain/auth/usecases/sign_in_with_email_password.dart';
import '../domain/auth/usecases/sign_out.dart';
import '../domain/auth/usecases/sign_up_with_email_password.dart';

void registerDomain(GetIt getIt) {
  getIt.registerLazySingleton<AuthGatePolicy>(() => const AuthGatePolicy());

  getIt.registerLazySingleton<SignInWithEmailPassword>(
    () => SignInWithEmailPassword(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton<SignUpWithEmailPassword>(
    () => SignUpWithEmailPassword(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton<ForgotPassword>(
    () => ForgotPassword(getIt<AuthRepository>()),
  );
  getIt.registerLazySingleton<SignOut>(
    () => SignOut(getIt<AuthRepository>()),
  );
}
