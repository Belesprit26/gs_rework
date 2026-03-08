/// Domain contract for app-level remote configuration.
abstract class RemoteConfigRepository {
  /// Fetch and activate the latest remote config values.
  Future<void> initialize();

  /// Whether the app should display a maintenance screen.
  bool get isMaintenanceMode;

  /// The minimum supported app version string (e.g. "1.0.5").
  String get minSupportedVersion;
}
