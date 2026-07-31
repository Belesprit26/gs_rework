import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../di/locator.dart';
import '../../data/local/prefs_manager.dart';
import '../../domain/notifications/entities/device_notification.dart';
import '../../domain/notifications/repositories/notification_repository.dart';
import '../ble/ble_connection_cubit.dart';

/// Full-page view for browsing device notifications.
///
/// Shows all notifications (BLE and remote). Muted types appear
/// with subdued styling. Notifications are not dismissible — they
/// stack up permanently and auto-delete after 7 days.
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
    final bleMac = bleState.pairedDeviceId;
    final deviceId = bleMac != null ? _prefs.getRtdbDeviceId(bleMac) : null;
    if (deviceId == null) {
      setState(() => _loading = false);
      return;
    }

    final items = await _repo.getUndismissed(deviceId);
    if (mounted) setState(() { _notifications = items; _loading = false; });
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
                    final isMuted = !_prefs.isNotificationTypeEnabled(n.type);
                    return _NotificationTile(
                      notification: n,
                      isMuted: isMuted,
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
    required this.isMuted,
  });

  final DeviceNotification notification;
  final bool isMuted;

  @override
  Widget build(BuildContext context) {
    final color = isMuted ? Colors.grey : _colorForType(notification.type);
    final time = _formatTime(notification.timestamp.toLocal());
    final isRemote = notification.source == NotificationSource.remote;

    return Opacity(
      opacity: isMuted ? 0.5 : 1.0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(
            _iconForType(notification.type),
            color: color,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                notification.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            Icon(
              isRemote ? Icons.wifi : Icons.bluetooth,
              size: 14,
              color: isMuted
                  ? Colors.grey.shade400
                  : isRemote
                      ? Colors.green.shade400
                      : Colors.blue.shade400,
            ),
          ],
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
      case NotificationType.sensorFail:
        return Colors.orange;
      case NotificationType.sensorRecover:
        return Colors.teal;
      case NotificationType.maxOnTimeout:
        return Colors.deepOrange;
      case NotificationType.clockLost:
        return Colors.orange;
      case NotificationType.scheduleRestored:
        return Colors.teal;
      case NotificationType.unknown:
        return Colors.grey;
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
      case NotificationType.sensorFail:
        return Icons.sensors_off;
      case NotificationType.sensorRecover:
        return Icons.sensors;
      case NotificationType.maxOnTimeout:
        return Icons.timer_off_outlined;
      case NotificationType.clockLost:
        return Icons.schedule_outlined;
      case NotificationType.scheduleRestored:
        return Icons.schedule;
      case NotificationType.unknown:
        return Icons.help_outline;
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
