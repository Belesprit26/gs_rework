part of 'login_bloc.dart';

enum LoginStatus { idle, submitting, success, failure }

class LoginState extends Equatable {
  const LoginState({
    this.email = '',
    this.password = '',
    this.status = LoginStatus.idle,
    this.error,
    this.forgotPasswordSent = false,
  });

  final String email;
  final String password;
  final LoginStatus status;
  final String? error;
  final bool forgotPasswordSent;

  LoginState copyWith({
    String? email,
    String? password,
    LoginStatus? status,
    String? error,
    bool? forgotPasswordSent,
  }) {
    return LoginState(
      email: email ?? this.email,
      password: password ?? this.password,
      status: status ?? this.status,
      error: error,
      forgotPasswordSent: forgotPasswordSent ?? this.forgotPasswordSent,
    );
  }

  @override
  List<Object?> get props => [email, password, status, error, forgotPasswordSent];
}
