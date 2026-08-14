import Flutter
import UIKit
import UserNotifications
// Module is `workmanager_apple` — the plugin split its Apple pod out
// under that name; `import workmanager` does not resolve and fails the
// Swift build.
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register the workmanager background task for daily telemetry sync.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    // Register the BGTaskScheduler launch handler for the daily sync.
    // Without this native-side registration the Dart-side
    // registerPeriodicTask submits a BGAppRefreshTaskRequest for an
    // unknown identifier and the task never executes.
    // Identifier must match kDailySyncTaskId in Dart and
    // BGTaskSchedulerPermittedIdentifiers in Info.plist.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.geyserswitch.dailySync",
      frequency: NSNumber(value: 24 * 60 * 60)
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Clear the home-screen icon badge whenever the app comes to the front.
  ///
  /// The push payload sends a fixed `badge: 1` (functions/index.js) — APNs
  /// has no server-side increment, and a true count is impossible anyway
  /// because read/dismissed state lives only in the on-device database.
  /// So the icon badge is a "something arrived while you were away" marker,
  /// not a count, and it has to be cleared by the app. Without this it
  /// stuck at 1 forever, which is what made it look like it disagreed with
  /// the in-app bell.
  ///
  /// Done natively rather than through a Dart channel so it also clears on
  /// a cold launch, before the Flutter engine is up.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0)
    } else {
      application.applicationIconBadgeNumber = 0
    }
  }
}
