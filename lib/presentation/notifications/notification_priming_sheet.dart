import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../data/firebase/fcm/push_notification_manager.dart';
import '../../di/locator.dart';
import '../theme/app_colors.dart';

/// Explains what the app will tell the user about — and what it keeps —
/// before asking for the OS notification permission.
///
/// Shown after a geyser is successfully set up, which is the moment the
/// value is self-evident rather than abstract. Asking cold at launch
/// costs opt-ins, and on iOS the system dialog is one-shot: decline once
/// and it can never be shown again, leaving system settings as the only
/// way back.
///
/// Safe to call at any time — it decides for itself whether to prompt,
/// to offer a route to settings, or to do nothing at all.
class NotificationPrimingSheet extends StatelessWidget {
  const NotificationPrimingSheet._({required this.isDenied});

  /// True when the OS has already been asked and refused, so the only
  /// remaining route is system settings.
  final bool isDenied;

  /// Show the sheet if it would be useful. Does nothing when
  /// notifications are already authorised.
  static Future<void> maybeShow(BuildContext context) async {
    final manager = getIt<PushNotificationManager>();
    final status = await manager.refreshAuthorizationStatus();

    switch (status) {
      case AuthorizationStatus.authorized:
      case AuthorizationStatus.provisional:
        return; // Nothing to ask for.
      case AuthorizationStatus.denied:
      case AuthorizationStatus.notDetermined:
        break;
    }

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.neuBase,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => NotificationPrimingSheet._(
        isDenied: status == AuthorizationStatus.denied,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text(
            'Keep an eye on your geyser',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 20),

          const _Reason(
            icon: Icons.notifications_active_outlined,
            title: 'Know when something needs you',
            body: 'Your geyser looks after itself day to day. We only get '
                'in touch when it is worth knowing — the water reached '
                'your set temperature, a heating session ran longer than '
                'you allowed, or the temperature sensor stopped '
                'responding. No chatter, just the things you would want '
                'to hear about.',
          ),
          const SizedBox(height: 18),
          const _Reason(
            icon: Icons.insights_outlined,
            title: 'Keep your usage history',
            body: 'Readings are recorded on your phone and backed up to '
                'your private account once a day. That is what lets you '
                'compare this month against last, see what your schedule '
                'is actually saving, and pick up where you left off on a '
                'new phone. It stays yours — nobody else can see it.',
          ),

          const SizedBox(height: 26),

          if (isDenied) ...[
            Text(
              'Notifications are currently switched off for GeyserSwitch. '
              'You can turn them back on in your device settings.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () async {
                  await openAppSettings();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Open settings'),
              ),
            ),
          ] else
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: () async {
                  await getIt<PushNotificationManager>()
                      .requestPermissionNow();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Turn on notifications'),
              ),
            ),

          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                isDenied ? 'Not now' : 'Maybe later',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reason extends StatelessWidget {
  const _Reason({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 22, color: AppColors.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
