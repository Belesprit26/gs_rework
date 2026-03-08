import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../di/locator.dart';
import '../../data/local/prefs_manager.dart';
import '../../domain/notifications/entities/device_notification.dart';
import '../../domain/notifications/repositories/notification_repository.dart';
import '../ble/ble_connection_cubit.dart';
import 'notification_service.dart';

/// Full-page view for browsing device notifications.
///
/// Shows undismissed notifications filtered by the user's enabled types.
/// Swipe-to-dismiss marks a notification as dismissed (UI-only removal).
/// Records are still stored and synced; they auto-delete after 7 days.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const NotificationsPage());

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _repo = getIt<NotificationRepository>();
  final _prefs = getIt<PrefsManager>();

  List<DeviceNotification> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bleState = context.read<BleConnectionCubit>().state;
    final deviceId = bleState.pairedDeviceId;
    if (deviceId == null) {
      setState(() => _loading = false);
      return;
    }

    final items = await _repo.getUndismissed(
      deviceId,
      enabledTypes: _prefs.enabledNotificationTypes,
    );
    if (mounted) setState(() { _notifications = items; _loading = false; });
  }

  Future<void> _dismiss(DeviceNotification n) async {
    if (n.id == null) return;
    await _repo.markDismissed(n.id!);
    setState(() => _notifications.removeWhere((x) => x.id == n.id));
    // Refresh the service's unread count.
    getIt<NotificationService>().refreshUnreadCount();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Events from your geyser will appear here',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey.shade600,
                            ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _notifications.length,
                  itemBuilder: (ctx, i) {
                    final n = _notifications[i];
                    return _NotificationTile(
                      notification: n,
                      onDismiss: () => _dismiss(n),
                    );
                  },
                ),
    );
  }
}

// ── Notification tile ────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onDismiss,
  });

  final DeviceNotification notification;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final color = _colorForType(notification.type);
    final time = _formatTime(notification.timestamp.toLocal());

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade100,
        child: const Icon(Icons.delete_outline, color: Colors.red),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(_iconForType(notification.type), color: color, size: 20),
        ),
        title: Text(
          notification.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          notification.body,
          style: const TextStyle(fontSize: 13),
        ),
        trailing: Text(
          time,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Color _colorForType(NotificationType type) {
    switch (type) {
      case NotificationType.maxTempOff:
        return Colors.red;
      case NotificationType.minTempOn:
        return Colors.green;
      case NotificationType.minTempAlert:
        return Colors.orange;
    }
  }

  IconData _iconForType(NotificationType type) {
    switch (type) {
      case NotificationType.maxTempOff:
        return Icons.thermostat;
      case NotificationType.minTempOn:
        return Icons.local_fire_department;
      case NotificationType.minTempAlert:
        return Icons.warning_amber_rounded;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final time = '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';

    if (date == today) return time;
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Yesterday $time';
    }
    return '${dt.day}/${dt.month} $time';
  }
}
