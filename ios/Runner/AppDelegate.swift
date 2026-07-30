import Flutter
import UIKit
import workmanager

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
}
