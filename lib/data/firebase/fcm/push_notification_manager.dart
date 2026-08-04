import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../../core/debug/debug_log.dart';
import '../../../domain/notifications/entities/device_notification.dart';
import '../../../domain/notifications/repositories/notification_repository.dart';
import '../../../firebase_options.dart';
import '../../local/app_database.dart';
import '../../local/drift_notification_repository.dart';
import '../../local/prefs_manager.dart';
import '../../../presentation/notifications/notification_service.dart';
import '../../../presentation/notifications/notifications_page.dart';

const _channelId = 'geyser_alerts';
const _channelName = 'Geyser Alerts';
const _channelDesc = 'Temperature events and device status alerts';

/// Top-level handler — runs in its own isolate when the app is terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final data = message.data;
  final typeStr = data['type'];
  final tempStr = data['temp'];
  final deviceId = data['deviceId'];

  if (typeStr == null || tempStr == null || deviceId == null) return;

  final typeCode = int.tryParse(typeStr);
  final temp = int.tryParse(tempStr);
  if (typeCode == null || temp == null) return;

  final db = AppDatabase();
  try {
    final repo = DriftNotificationRepository(db: db);

    final type = NotificationType.fromCode(typeCode);
    final now = DateTime.now().toUtc();

    final exists = await repo.hasMatchingEvent(
      deviceId: deviceId,
      type: type,
      timestamp: now,
    );

    if (!exists) {
      await repo.insert(DeviceNotification(
        deviceId: deviceId,
        type: type,
        temperature: temp,
        timestamp: now,
        source: NotificationSource.remote,
      ));

      debugLog('FCM-bg',
          'Inserted remote notification: ${type.label} @ $temp°C');
    }
  } finally {
    await db.close();
  }
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
/// 6. Bridges incoming FCM data payloads into the local Drift
///    database so remote events appear in the in-app notification
///    list, deduplicating against BLE-delivered events.
/// 7. Handles notification taps to navigate to the notifications page.
class PushNotificationManager {
  PushNotificationManager({
    required FirebaseMessaging messaging,
    required FirebaseFunctions functions,
    required NotificationRepository notificationRepository,
    required PrefsManager prefsManager,
    required NotificationService notificationService,
  })  : _messaging = messaging,
        _functions = functions,
        _notificationRepo = notificationRepository,
        _prefs = prefsManager,
        _notificationService = notificationService;

  final FirebaseMessaging _messaging;
  final FirebaseFunctions _functions;
  final NotificationRepository _notificationRepo;
  final PrefsManager _prefs;
  final NotificationService _notificationService;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _initializing = false;
  StreamSubscription<String>? _tokenRefreshSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _messageOpenedSub;

  AuthorizationStatus _authorizationStatus = AuthorizationStatus.notDetermined;

  /// The OS notification permission as last observed. Note this only
  /// governs whether alerts can be DISPLAYED — message delivery, the
  /// in-app notification list and token registration all work without
  /// it.
  AuthorizationStatus get authorizationStatus => _authorizationStatus;

  /// Global navigator key — set on [MaterialApp] to allow navigation
  /// from notification taps outside the widget tree.
  static final navigatorKey = GlobalKey<NavigatorState>();

  /// The local-notification plugin, exposed so a future BLE foreground
  /// service can show notifications through the same channel.
  FlutterLocalNotificationsPlugin get localNotifications => _localNotifications;

  // ── Public API ────────────────────────────────────────────────────

  /// Call once from `main()` after Firebase.initializeApp and DI setup.
  ///
  /// The OS permission governs only whether alerts can be DISPLAYED.
  /// Everything else here — token registration, the message handlers,
  /// and bridging remote events into the local notification list — is
  /// permission-independent and is wired up regardless of the answer.
  /// Bailing out on a denial (as this used to) silently cost the user
  /// their in-app event history and made the install unreachable by the
  /// backend even for data-only messages.
  Future<void> initialize() async {
    // Guard re-entry, but do NOT latch until the work succeeds: a
    // transient failure must leave a later retry possible.
    if (_initialized || _initializing) return;
    _initializing = true;

    try {
      FirebaseMessaging.onBackgroundMessage(
          firebaseMessagingBackgroundHandler);

      // Read the current status WITHOUT prompting. The ask itself is
      // deliberately not made here: at launch the user has no context
      // for it, and on iOS the dialog is one-shot. It is made instead
      // by NotificationPrimingSheet, once a geyser is set up and the
      // value is obvious. Users who already granted are unaffected.
      final settings = await _messaging.getNotificationSettings();
      _authorizationStatus = settings.authorizationStatus;

      // Needed to display alerts; harmless when permission is absent.
      await _setupLocalNotifications();

      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // Token registration is isolated: on iOS getToken can fail while
      // the APNS token is still pending, and that must not prevent the
      // handlers below from being attached.
      try {
        final token = await _messaging.getToken();
        if (token != null) {
          await _registerToken(token);
        }
      } catch (e) {
        debugLog('FCM', 'Initial token fetch failed: $e');
      }
      _tokenRefreshSub = _messaging.onTokenRefresh.listen(_registerToken);

      // _onForegroundMessage bridges the event into the local DB before
      // it displays anything — that half needs no permission.
      _foregroundSub = FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      _messageOpenedSub =
          FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationTapped);

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _onNotificationTapped(initialMessage);
      }

      _initialized = true;
      debugLog('FCM', 'Initialized — permission=$_authorizationStatus');
    } finally {
      _initializing = false;
    }
  }

  /// Show the OS permission prompt.
  ///
  /// Call only from a context where the user has just been told what
  /// notifications are for — see [NotificationPrimingSheet]. On iOS the
  /// system dialog appears at most once in the app's lifetime; after a
  /// refusal this returns the existing status without prompting, and
  /// system settings become the only route back.
  Future<AuthorizationStatus> requestPermissionNow() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      _authorizationStatus = settings.authorizationStatus;
      debugLog('FCM', 'Permission requested — result=$_authorizationStatus');
    } catch (e) {
      debugLog('FCM', 'Permission request failed: $e');
    }
    return _authorizationStatus;
  }

  /// Re-read the OS permission without prompting. Call after the app
  /// returns from the background so a change made in system settings is
  /// reflected without a relaunch.
  Future<AuthorizationStatus> refreshAuthorizationStatus() async {
    try {
      final settings = await _messaging.getNotificationSettings();
      _authorizationStatus = settings.authorizationStatus;
    } catch (e) {
      debugLog('FCM', 'Permission status refresh failed: $e');
    }
    return _authorizationStatus;
  }

  /// Cancel all stream subscriptions. Safe to call even if not initialized.
  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    await _foregroundSub?.cancel();
    await _messageOpenedSub?.cancel();
    _tokenRefreshSub = null;
    _foregroundSub = null;
    _messageOpenedSub = null;
    _initialized = false;
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

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (_) {
        _navigateToNotifications();
      },
    );

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
      debugLog('FCM', 'Token registered with backend');
    } catch (e) {
      debugLog('FCM', 'Token registration failed: $e');
    }
  }

  /// Invalidate this install's FCM token — call on sign-out so the
  /// phone stops receiving the account's geyser alerts. The backend's
  /// send path prunes the (now unregistered) token from Firestore on
  /// its next delivery attempt.
  Future<void> unregisterToken() async {
    try {
      await _messaging.deleteToken();
      debugLog('FCM', 'Token deleted on sign-out');
    } catch (e) {
      debugLog('FCM', 'Token delete failed: $e');
    }
  }

  /// Register the install's current token under the signed-in user —
  /// call after a sign-in. Needed because sign-out deletes the token,
  /// and a refresh that fires while signed out cannot be registered
  /// (the callable requires auth), so onTokenRefresh alone is not
  /// enough for a same-session account switch.
  Future<void> refreshRegistration() async {
    if (!_initialized) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) await _registerToken(token);
    } catch (e) {
      debugLog('FCM', 'Token re-registration failed: $e');
    }
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    await _bridgeToLocalDb(message);

    final notification = message.notification;
    if (notification == null) return;

    final typeStr = message.data['type'];
    if (typeStr != null) {
      final typeCode = int.tryParse(typeStr);
      if (typeCode != null) {
        final type = NotificationType.fromCode(typeCode);
        if (!_prefs.isNotificationTypeEnabled(type)) {
          return;
        }
      }
    }

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

  void _onNotificationTapped(RemoteMessage message) {
    _bridgeToLocalDb(message);
    _navigateToNotifications();
  }

  void _navigateToNotifications() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(NotificationsPage.route());
    });
  }

  /// Insert the FCM event into local Drift DB if it wasn't already
  /// delivered via BLE. Deduplicates on (deviceId, type, timestamp ± 2 min).
  Future<void> _bridgeToLocalDb(RemoteMessage message) async {
    final data = message.data;
    final typeStr = data['type'];
    final tempStr = data['temp'];
    final deviceId = data['deviceId'];

    if (typeStr == null || tempStr == null || deviceId == null) return;

    final typeCode = int.tryParse(typeStr);
    final temp = int.tryParse(tempStr);
    if (typeCode == null || temp == null) return;

    final type = NotificationType.fromCode(typeCode);
    final now = DateTime.now().toUtc();

    try {
      final exists = await _notificationRepo.hasMatchingEvent(
        deviceId: deviceId,
        type: type,
        timestamp: now,
      );

      if (exists) {
        debugLog('FCM',
            'Duplicate event (BLE already delivered): ${type.label} @ $temp°C');
        return;
      }

      await _notificationRepo.insert(DeviceNotification(
        deviceId: deviceId,
        type: type,
        temperature: temp,
        timestamp: now,
        source: NotificationSource.remote,
      ));

      _notificationService.refreshUnreadCount();

      debugLog('FCM',
          'Bridged remote notification: ${type.label} @ $temp°C');
    } catch (e) {
      debugLog('FCM', 'Bridge to local DB failed: $e');
    }
  }
}
