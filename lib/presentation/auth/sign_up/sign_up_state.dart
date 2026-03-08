part of 'sign_up_bloc.dart';

enum SignUpStatus { idle, submitting, success, failure }

class SignUpState extends Equatable {
  const SignUpState({
    this.email = '',
    this.password = '',
    this.fullName = '',
    this.status = SignUpStatus.idle,
    this.error,
  });

  final String email;
  final String password;
  final String fullName;
  final SignUpStatus status;
  final String? error;

  SignUpState copyWith({
    String? email,
    String? password,
    String? fullName,
    SignUpStatus? status,
    String? error,
  }) {
    return SignUpState(
      email: email ?? this.email,
      password: password ?? this.password,
      fullName: fullName ?? this.fullName,
      status: status ?? this.status,
      error: error,
    );
  }

  @override
  List<Object?> get props => [email, password, fullName, status, error];
}
