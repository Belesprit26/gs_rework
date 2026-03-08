import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _channelId = 'geyser_alerts';
const _channelName = 'Geyser Alerts';
const _channelDesc = 'Temperature events and device status alerts';

/// Top-level handler — runs in its own isolate when the app is terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Notification-type messages are shown automatically by the OS.
  // This handler exists for future data-only processing if needed.
}

/// Manages the full FCM lifecycle:
///
/// 1. Requests notification permission (shows OS dialog once).
/// 2. Retrieves the FCM token and registers it with the backend
///    via the `registerFcmToken` Cloud Function.
/// 3. Listens for token refresh and re-registers automatically.
/// 4. Creates an Android notification channel (`geyser_alerts`).
/// 5. Shows a local notification for messages received while the
///    app is in the foreground (background messages are handled
///    automatically by the OS).
///
/// Designed so a future Android foreground-service BLE monitor can
/// reuse the same notification channel and local-notification plugin
/// without any changes to this class.
class PushNotificationManager {
  PushNotificationManager({
    required FirebaseMessaging messaging,
    required FirebaseFunctions functions,
  })  : _messaging = messaging,
        _functions = functions;

  final FirebaseMessaging _messaging;
  final FirebaseFunctions _functions;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// The local-notification plugin, exposed so a future BLE foreground
  /// service can show notifications through the same channel.
  FlutterLocalNotificationsPlugin get localNotifications => _localNotifications;

  // ── Public API ────────────────────────────────────────────────────

  /// Call once from `main()` after Firebase.initializeApp and DI setup.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler);

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (kDebugMode) {
        debugPrint('[FCM] Notification permission denied by user');
      }
      return;
    }

    await _setupLocalNotifications();

    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await _messaging.getToken();
    if (token != null) {
      await _registerToken(token);
    }

    _messaging.onTokenRefresh.listen(_registerToken);

    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    if (kDebugMode) {
      debugPrint('[FCM] Initialized — permission=${settings.authorizationStatus}');
    }
  }

  // ── Private ───────────────────────────────────────────────────────

  Future<void> _setupLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(initSettings);

    if (Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    }
  }

  Future<void> _registerToken(String token) async {
    try {
      await _functions.httpsCallable('registerFcmToken').call({
        'token': token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      if (kDebugMode) {
        debugPrint('[FCM] Token registered with backend');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[FCM] Token registration failed: $e');
      }
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      notification.title,
      notification.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
