part of 'auth_gate_cubit.dart';

class AuthGateState extends Equatable {
  const AuthGateState._({
    required this.decision,
    required this.user,
  });

  const AuthGateState.loading()
      : this._(decision: AuthGateDecision.loading, user: null);

  const AuthGateState.ready({
    required AuthUser? user,
    required AuthGateDecision decision,
  }) : this._(decision: decision, user: user);

  final AuthGateDecision decision;
  final AuthUser? user;

  @override
  List<Object?> get props => [decision, user];
}

