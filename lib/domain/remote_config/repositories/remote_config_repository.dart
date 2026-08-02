/// Domain contract for app-level remote configuration.
abstract class RemoteConfigRepository {
  /// Fetch and activate the latest remote config values.
  Future<void> initialize();

  /// Whether the app should display a maintenance screen.
  bool get isMaintenanceMode;

  /// The minimum supported app version string (e.g. "1.0.5").
  String get minSupportedVersion;

  /// Standing heat loss (kWh per 24 h) for a tank of [tankSizeLitres] —
  /// the energy an idle, permanently-powered geyser burns just holding
  /// temperature. This is what a scheduling product actually saves, so
  /// it sets the whole savings figure.
  ///
  /// Remote so it can be recalibrated against real metered installs
  /// without shipping an app release.
  double standingLossKwhPerDay(int tankSizeLitres);
}
