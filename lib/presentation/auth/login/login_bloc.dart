import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/result/result.dart';
import '../../../di/locator.dart';
import '../../../domain/auth/usecases/forgot_password.dart';
import '../../../domain/auth/usecases/sign_in_with_email_password.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc({
    SignInWithEmailPassword? signIn,
    ForgotPassword? forgotPassword,
  })  : _signIn = signIn ?? getIt<SignInWithEmailPassword>(),
        _forgotPassword = forgotPassword ?? getIt<ForgotPassword>(),
        super(const LoginState()) {
    on<LoginEmailChanged>((e, emit) => emit(state.copyWith(email: e.email)));
    on<LoginPasswordChanged>((e, emit) => emit(state.copyWith(password: e.password)));
    on<LoginSubmitted>(_onSubmit);
    on<LoginForgotPasswordPressed>(_onForgotPassword);
  }

  final SignInWithEmailPassword _signIn;
  final ForgotPassword _forgotPassword;

  Future<void> _onSubmit(LoginSubmitted event, Emitter<LoginState> emit) async {
    // Client-side validation
    final validationError = _validate();
    if (validationError != null) {
      emit(state.copyWith(status: LoginStatus.failure, error: validationError));
      return;
    }

    emit(state.copyWith(status: LoginStatus.submitting, error: null));
    final res = await _signIn(email: state.email, password: state.password);
    switch (res) {
      case Err(failure: final f):
        emit(state.copyWith(status: LoginStatus.failure, error: f.message));
      case Ok():
        emit(state.copyWith(status: LoginStatus.success));
    }
  }

  Future<void> _onForgotPassword(
    LoginForgotPasswordPressed event,
    Emitter<LoginState> emit,
  ) async {
    final email = state.email.trim();
    if (email.isEmpty || !_isValidEmail(email)) {
      emit(state.copyWith(
        error: 'Enter a valid email address first.',
        forgotPasswordSent: false,
      ));
      return;
    }

    emit(state.copyWith(status: LoginStatus.submitting, error: null));
    final res = await _forgotPassword(email: email);
    switch (res) {
      case Err(failure: final f):
        emit(state.copyWith(
          status: LoginStatus.failure,
          error: f.message,
          forgotPasswordSent: false,
        ));
      case Ok():
        emit(state.copyWith(
          status: LoginStatus.idle,
          error: null,
          forgotPasswordSent: true,
        ));
    }
  }

  // ── Validation helpers ──────────────────────────────────────────────

  String? _validate() {
    final email = state.email.trim();
    final password = state.password;

    if (email.isEmpty) return 'Email is required.';
    if (!_isValidEmail(email)) return 'Enter a valid email address.';
    if (password.isEmpty) return 'Password is required.';
    if (password.length < 6) return 'Password must be at least 6 characters.';
    return null;
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[\w\-.+]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(value);
  }
}
