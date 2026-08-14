import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../di/locator.dart';
import '../../data/local/prefs_manager.dart';
import '../../domain/notifications/entities/device_notification.dart';
import '../../domain/notifications/repositories/notification_repository.dart';
import '../device/device_registry_cubit.dart';
import '../shared/feedback/haptics.dart';

/// Full-page view for browsing device notifications.
///
/// Pools notifications across EVERY registered geyser into one list,
/// newest first, each row labelled by its device — a problem on one
/// geyser shouldn't be hidden because you're viewing another. Shows all
/// notifications (BLE and remote); muted types appear subdued.
/// Not dismissible — they auto-delete after 7 days.
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

  /// The device the list is filtered to, or null for all devices.
  String? _deviceFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Pooled across all devices — not scoped to the connected one.
    final items = await _repo.getAllUndismissed();
    if (mounted) setState(() { _notifications = items; _loading = false; });

    // Opening the list is what "reading" means, so mark on load rather
    // than on dispose: anything arriving while the page is open stays
    // unread and correctly re-badges the bell on the way out.
    await _repo.markAllRead();
  }

  /// Distinct device ids present, most-recently-active first (the list
  /// is newest-first). Drives the filter chips and the per-row label.
  List<String> get _devicesPresent =>
      LinkedHashSet<String>.of(_notifications.map((n) => n.deviceId))
          .toList();

  bool get _isMultiDevice => _devicesPresent.length > 1;

  /// The list after applying the device filter.
  List<DeviceNotification> get _visible {
    final filter = _deviceFilter;
    if (filter == null) return _notifications;
    return _notifications.where((n) => n.deviceId == filter).toList();
  }

  /// A readable name for a device id: its registry nickname, else the
  /// prefs nickname (survives a removed device), else the raw id.
  String _deviceLabel(String rtdbDeviceId) {
    final registry = context.read<DeviceRegistryCubit>().state;
    for (final d in registry.devices) {
      if (d.rtdbDeviceId == rtdbDeviceId) return d.nickname;
    }
    return _prefs.getDeviceNickname(rtdbDeviceId) ?? 'Geyser';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const _EmptyState(
                  message: 'Events from your geyser will appear here',
                )
              : Column(
                  children: [
                    if (_isMultiDevice) _buildDeviceFilter(),
                    Expanded(
                      child: visible.isEmpty
                          ? const _EmptyState(
                              message: 'No notifications for this geyser')
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8),
                              itemCount: visible.length,
                              itemBuilder: (ctx, i) {
                                final n = visible[i];
                                final isMuted =
                                    !_prefs.isNotificationTypeEnabled(n.type);
                                return _NotificationTile(
                                  notification: n,
                                  isMuted: isMuted,
                                  // Once filtered to one device, the
                                  // per-row label is redundant.
                                  deviceLabel: _deviceFilter == null
                                      ? _deviceLabel(n.deviceId)
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }

  /// A horizontal chip row: All + one chip per device with events.
  Widget _buildDeviceFilter() {
    final devices = _devicesPresent;
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _FilterChip(
            label: 'All',
            selected: _deviceFilter == null,
            onTap: () => setState(() => _deviceFilter = null),
          ),
          for (final id in devices)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _FilterChip(
                label: _deviceLabel(id),
                selected: _deviceFilter == id,
                onTap: () => setState(() => _deviceFilter = id),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Filter chip ──────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        if (!selected) Haptics.select();
        onTap();
      },
      showCheckmark: false,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected ? primary : Colors.grey.shade700,
      ),
      selectedColor: primary.withValues(alpha: 0.12),
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(
        color: selected ? primary.withValues(alpha: 0.4) : Colors.transparent,
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('No notifications',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }
}

// ── Notification tile ────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.isMuted,
    this.deviceLabel,
  });

  final DeviceNotification notification;
  final bool isMuted;

  /// Which geyser this came from. Null in single-device households,
  /// where the label would be noise.
  final String? deviceLabel;

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
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (deviceLabel != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.water_drop_outlined,
                      size: 12, color: color.withValues(alpha: 0.8)),
                  const SizedBox(width: 3),
                  Text(
                    deviceLabel!,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
            ],
            Text(
              notification.body,
              style: const TextStyle(fontSize: 13),
            ),
          ],
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
      case NotificationType.leak:
        return Colors.red;
      case NotificationType.leakClear:
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
      case NotificationType.leak:
        return Icons.water_damage;
      case NotificationType.leakClear:
        return Icons.check_circle_outline;
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
