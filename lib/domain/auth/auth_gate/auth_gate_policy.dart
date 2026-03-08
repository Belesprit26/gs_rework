import 'auth_gate_context.dart';
import 'auth_gate_decision.dart';

/// Pure decision logic for the auth gate.
///
/// This keeps navigation rules out of the Cubit/UI and makes them unit-testable.
class AuthGatePolicy {
  const AuthGatePolicy();

  AuthGateDecision decide(AuthGateContext ctx) {
    if (ctx.isMaintenanceMode) return AuthGateDecision.maintenance;
    if (!ctx.isMinVersionSupported) return AuthGateDecision.forceUpgrade;

    final user = ctx.user;
    if (user == null) return AuthGateDecision.signedOut;

    if (!ctx.isProfileComplete) return AuthGateDecision.needsProfile;

    return AuthGateDecision.ready;
  }
}

