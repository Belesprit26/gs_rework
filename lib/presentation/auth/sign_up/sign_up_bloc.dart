import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/result/result.dart';
import '../../../di/locator.dart';
import '../../../domain/auth/usecases/sign_up_with_email_password.dart';

part 'sign_up_event.dart';
part 'sign_up_state.dart';

class SignUpBloc extends Bloc<SignUpEvent, SignUpState> {
  SignUpBloc({SignUpWithEmailPassword? signUp})
      : _signUp = signUp ?? getIt<SignUpWithEmailPassword>(),
        super(const SignUpState()) {
    on<SignUpEmailChanged>((e, emit) => emit(state.copyWith(email: e.email)));
    on<SignUpPasswordChanged>((e, emit) => emit(state.copyWith(password: e.password)));
    on<SignUpFullNameChanged>((e, emit) => emit(state.copyWith(fullName: e.fullName)));
    on<SignUpSubmitted>(_onSubmit);
  }

  final SignUpWithEmailPassword _signUp;

  Future<void> _onSubmit(SignUpSubmitted event, Emitter<SignUpState> emit) async {
    // Client-side validation
    final validationError = _validate();
    if (validationError != null) {
      emit(state.copyWith(status: SignUpStatus.failure, error: validationError));
      return;
    }

    emit(state.copyWith(status: SignUpStatus.submitting, error: null));

    final res = await _signUp(
      email: state.email,
      fullName: state.fullName,
      password: state.password,
    );

    switch (res) {
      case Err(failure: final f):
        emit(state.copyWith(status: SignUpStatus.failure, error: f.message));
      case Ok():
        emit(state.copyWith(status: SignUpStatus.success));
    }
  }

  // ── Validation helpers ──────────────────────────────────────────────

  String? _validate() {
    final fullName = state.fullName.trim();
    final email = state.email.trim();
    final password = state.password;

    if (fullName.isEmpty) return 'Name is required.';
    if (fullName.length < 2) return 'Name must be at least 2 characters.';
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
