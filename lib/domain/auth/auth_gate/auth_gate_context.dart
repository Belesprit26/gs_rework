import '../entities/auth_user.dart';

/// Input to the auth gate decision logic.
///
/// Keep this pure and serializable-ish so it’s easy to unit test.
class AuthGateContext {
  const AuthGateContext({
    required this.user,
    this.isProfileComplete = true,
    this.isMaintenanceMode = false,
    this.isMinVersionSupported = true,
  });

  final AuthUser? user;

  /// If false, route user to profile completion.
  final bool isProfileComplete;

  /// If true, app should show maintenance screen regardless of auth.
  final bool isMaintenanceMode;

  /// If false, app should show force-upgrade screen regardless of auth.
  final bool isMinVersionSupported;
}

