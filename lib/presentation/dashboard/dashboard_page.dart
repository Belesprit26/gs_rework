import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/local/prefs_manager.dart';
import '../../di/locator.dart';
import '../../domain/auth/usecases/sign_out.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../../domain/geyser/entities/geyser_snapshot.dart';
import '../../domain/notifications/entities/device_notification.dart';
import '../ble/ble_connection_cubit.dart';
import '../ble/device_scan_page.dart';
import '../geyser/geyser_control_cubit.dart';
import '../notifications/notification_service.dart';
import '../notifications/notifications_page.dart';
import '../shared/widgets/geyser_focal_card.dart';
import '../shared/widgets/stat_tile.dart';

/// The main app shell after sign-in.
///
/// Contains a [Scaffold] with:
/// - An app bar (with BLE status chip + sign-out)
/// - Padded body content with a single focal card + stat tiles
/// - A bottom navigation bar (Devices tab opens BLE scan)
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    // Try to auto-connect to a previously paired device.
    context.read<BleConnectionCubit>().tryAutoConnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GS Rework'),
        actions: [
          const _NotificationBell(),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: () => _confirmSignOut(context),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: const [
          _HomeTab(),
          Center(child: Text('Devices – coming soon')),
          _SettingsTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (i) => setState(() => _currentTab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.devices_other_outlined),
            selectedIcon: Icon(Icons.devices_other_rounded),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sign out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    await getIt<SignOut>().call();
  }
}


// ── Home tab ────────────────────────────────────────────────────────

class _HomeTab extends StatelessWidget {
  const _HomeTab();

  @override
  Widget build(BuildContext context) {
    // Get the device nickname for the focal card label.
    final bleState = context.watch<BleConnectionCubit>().state;
    final nickname = bleState.deviceNickname;
    final geyserLabel = (nickname != null && nickname.isNotEmpty)
        ? nickname
        : 'Geyser';

    return BlocConsumer<GeyserControlCubit, GeyserControlState>(
      listenWhen: (prev, curr) =>
          prev.snapshot.isOn != curr.snapshot.isOn ||
          prev.error != curr.error,
      listener: (context, state) {
        // ── Snackbar feedback on toggle ────────────────────────
        if (state.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Command failed: ${state.error}'),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      builder: (context, state) {
        final snap = state.snapshot;

        // Build timer subtitle.
        final enabledTimers = snap.timers.where((t) => t.enabled).toList();
        final timerSubtitle = enabledTimers.isEmpty
            ? 'No timers active'
            : enabledTimers.map((t) => t.timeFormatted).join(' · ');

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // ── Focal card ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 46),
              child: GeyserFocalCard(
                name: geyserLabel,
                isOn: snap.isOn,
                temperature: snap.temperature,
                isLoading: state.isLoading,
                isBusy: state.isBusy,
                onToggle: () =>
                    context.read<GeyserControlCubit>().toggleGeyser(),
              ),
            ),
            const SizedBox(height: 12),

            // ── Mode / connectivity banner ───────────────────────
            const _ModeBanner(),
            const SizedBox(height: 12),

            // ── Section label ────────────────────────────────────
            Text(
              'Geyser Stats',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),

            // ── Stat tiles ───────────────────────────────────────
            StatTile(
              icon: Icons.thermostat_outlined,
              title: 'Temperature Range',
              subtitle: '${snap.minTemp}°C – ${snap.maxTemp}°C'
                  '${snap.autoReheat ? ' (auto-reheat)' : ''}',
              onTap: () => _showTempLimitsDialog(context, snap),
            ),
            const SizedBox(height: 8),
            StatTile(
              icon: Icons.timer_outlined,
              title: 'Active Timers',
              subtitle: timerSubtitle,
              onTap: () => _showTimerSettingsDialog(context, snap),
            ),
            const SizedBox(height: 8),
            StatTile(
              icon: Icons.info_outline,
              title: 'Firmware',
              subtitle: snap.firmwareVersion ?? '–',
            ),

            // ── Error banner ─────────────────────────────────────
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 24),
          ],
        );
      },
    );
  }

  // ── Timer settings dialog ──────────────────────────────────────────

  void _showTimerSettingsDialog(BuildContext context, GeyserSnapshot snap) {
    final cubit = context.read<GeyserControlCubit>();

    // Start with current timers. If empty (old firmware), seed defaults.
    final timers = snap.timers.isNotEmpty
        ? snap.timers.map((t) => t.copyWith()).toList()
        : [
            const GeyserTimer(hour: 4, minute: 0, isPreset: true, enabled: false),
            const GeyserTimer(hour: 6, minute: 0, isPreset: true, enabled: false),
            const GeyserTimer(hour: 15, minute: 0, isPreset: true, enabled: false),
            const GeyserTimer(hour: 17, minute: 0, isPreset: true, enabled: false),
            const GeyserTimer(hour: 6, minute: 0, isPreset: false, enabled: false),
          ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Timer Settings'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Timers turn the geyser ON at the scheduled time. '
                      'The thermostat (max temp) turns it OFF automatically.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                    ),
                    const SizedBox(height: 16),

                    // ── Preset timers ───────────────────────────────
                    Text(
                      'Off-Peak Presets',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < timers.length; i++)
                      if (timers[i].isPreset)
                        _PresetTimerRow(
                          timer: timers[i],
                          onToggle: (enabled) {
                            setDialogState(() {
                              timers[i] = timers[i].copyWith(enabled: enabled);
                            });
                          },
                        ),

                    const Divider(height: 24),

                    // ── Custom timer ────────────────────────────────
                    Text(
                      'Custom Timer',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (int i = 0; i < timers.length; i++)
                      if (!timers[i].isPreset)
                        _CustomTimerRow(
                          timer: timers[i],
                          onToggle: (enabled) {
                            setDialogState(() {
                              timers[i] = timers[i].copyWith(enabled: enabled);
                            });
                          },
                          onPickTime: () async {
                            final t = timers[i];
                            final picked = await showTimePicker(
                              context: ctx,
                              initialTime:
                                  TimeOfDay(hour: t.hour, minute: t.minute),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                timers[i] = t.copyWith(
                                  hour: picked.hour,
                                  minute: picked.minute,
                                );
                              });
                            }
                          },
                        ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  cubit.setTimers(timers);
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Temperature limits dialog ──────────────────────────────────────

  void _showTempLimitsDialog(BuildContext context, GeyserSnapshot snap) {
    final cubit = context.read<GeyserControlCubit>();
    var min = snap.minTemp;
    var max = snap.maxTemp;
    var autoReheat = snap.autoReheat;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Temperature Limits'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Min temp slider ────────────────────────────────
              Row(
                children: [
                  const Expanded(child: Text('Min')),
                  Text('$min°C'),
                ],
              ),
              Slider(
                min: 20,
                max: 55,
                divisions: 35,
                value: min.toDouble(),
                onChanged: (v) => setDialogState(() => min = v.round()),
              ),
              const SizedBox(height: 8),

              // ── Max temp slider ────────────────────────────────
              Row(
                children: [
                  const Expanded(child: Text('Max')),
                  Text('$max°C'),
                ],
              ),
              Slider(
                min: 30,
                max: 70,
                divisions: 40,
                value: max.toDouble(),
                onChanged: (v) => setDialogState(() => max = v.round()),
              ),
              const Divider(height: 24),

              // ── Auto-reheat toggle ─────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Auto-Reheat'),
                        Text(
                          autoReheat
                              ? 'Geyser turns ON when temp drops to min'
                              : 'You\'ll be alerted when temp drops to min',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: autoReheat,
                    onChanged: (v) =>
                        setDialogState(() => autoReheat = v),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                cubit.setTempLimits(
                  min: min,
                  max: max,
                  autoReheat: autoReheat,
                );
                Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Preset timer row ─────────────────────────────────────────────────

class _PresetTimerRow extends StatelessWidget {
  const _PresetTimerRow({
    required this.timer,
    required this.onToggle,
  });

  final GeyserTimer timer;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Time label (non-editable for presets).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              timer.timeFormatted,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: timer.enabled ? null : Colors.grey,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _offPeakLabel(timer.hour),
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          Switch(
            value: timer.enabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }

  String _offPeakLabel(int hour) {
    if (hour < 12) return 'Morning';
    return 'Afternoon';
  }
}

// ── Notification bell with badge ──────────────────────────────────────

class _NotificationBell extends StatefulWidget {
  const _NotificationBell();

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  late final NotificationService _service;
  StreamSubscription<int>? _sub;
  int _unread = 0;
  bool _anyEnabled = true;

  @override
  void initState() {
    super.initState();
    _service = getIt<NotificationService>();
    _unread = _service.currentUnreadCount;
    _anyEnabled = getIt<PrefsManager>().anyNotificationEnabled;
    _sub = _service.unreadCount.listen((count) {
      if (mounted) setState(() => _unread = count);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = _anyEnabled
        ? Icons.notifications_outlined
        : Icons.notifications_off_outlined;
    final color = _anyEnabled ? null : Colors.grey;

    return IconButton(
      icon: Badge(
        isLabelVisible: _unread > 0 && _anyEnabled,
        label: Text('$_unread', style: const TextStyle(fontSize: 10)),
        child: Icon(icon, color: color),
      ),
      tooltip: 'Notifications',
      onPressed: () async {
        await Navigator.of(context).push(NotificationsPage.route());
        // Refresh badge and enabled state when returning.
        _service.refreshUnreadCount();
        if (mounted) {
          setState(() {
            _anyEnabled = getIt<PrefsManager>().anyNotificationEnabled;
          });
        }
      },
    );
  }
}

// ── Settings tab ─────────────────────────────────────────────────────

class _SettingsTab extends StatefulWidget {
  const _SettingsTab();

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  @override
  Widget build(BuildContext context) {
    final prefs = getIt<PrefsManager>();
    final anyEnabled = prefs.anyNotificationEnabled;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Text(
          'Settings',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        ListTile(
          leading: Icon(
            anyEnabled
                ? Icons.notifications_outlined
                : Icons.notifications_off_outlined,
            color: anyEnabled ? null : Colors.grey,
          ),
          title: const Text('Notification Settings'),
          subtitle: Text(
            anyEnabled ? 'Some notifications enabled' : 'All notifications muted',
            style: TextStyle(
              color: anyEnabled ? null : Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await _showNotificationSettingsDialog(context);
            setState(() {}); // Refresh after changes.
          },
        ),
      ],
    );
  }

  Future<void> _showNotificationSettingsDialog(BuildContext context) async {
    final prefs = getIt<PrefsManager>();

    // Snapshot current state.
    final toggles = {
      for (final type in NotificationType.settable)
        type: prefs.isNotificationTypeEnabled(type),
    };

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Notification Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose which notifications you want to receive. '
                'Muted types still appear in the list but won\'t '
                'count toward your badge or trigger alerts.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 16),
              for (final type in NotificationType.settable)
                _NotificationTypeToggle(
                  type: type,
                  enabled: toggles[type] ?? true,
                  onChanged: (enabled) {
                    setDialogState(() => toggles[type] = enabled);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                for (final entry in toggles.entries) {
                  await prefs.setNotificationTypeEnabled(
                    entry.key,
                    entry.value,
                  );
                }
                // Refresh the badge count with new preferences.
                getIt<NotificationService>().refreshUnreadCount();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTypeToggle extends StatelessWidget {
  const _NotificationTypeToggle({
    required this.type,
    required this.enabled,
    required this.onChanged,
  });

  final NotificationType type;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            _iconForType(type),
            size: 20,
            color: enabled ? _colorForType(type) : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  type.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: enabled ? null : Colors.grey,
                  ),
                ),
                Text(
                  _descriptionForType(type),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),
          Switch(value: enabled, onChanged: onChanged),
        ],
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
      case NotificationType.unknown:
        return Icons.help_outline;
    }
  }

  String _descriptionForType(NotificationType type) {
    switch (type) {
      case NotificationType.maxTempOff:
        return 'When geyser auto-turns off at max temp';
      case NotificationType.minTempOn:
        return 'When geyser auto-turns on at min temp';
      case NotificationType.minTempAlert:
        return 'When temp drops to min (auto-reheat off)';
      case NotificationType.unknown:
        return 'Unknown event type';
    }
  }
}

// ── Mode / connectivity banner ────────────────────────────────────────

class _ModeBanner extends StatelessWidget {
  const _ModeBanner();

  @override
  Widget build(BuildContext context) {
    final gState = context.watch<GeyserControlCubit>().state;
    final bleState = context.watch<BleConnectionCubit>().state;
    final theme = Theme.of(context);

    final IconData icon;
    final String label;
    final Color color;
    VoidCallback? onTap;
    Widget? trailing;

    switch (gState.mode) {
      case GeyserMode.ble:
        icon = Icons.bluetooth_connected;
        label = 'Connected via Bluetooth';
        color = Colors.blue;

      case GeyserMode.remote:
        if (gState.deviceOffline) {
          icon = Icons.cloud_off_rounded;
          label = 'Device offline';
          color = Colors.orange;
          if (gState.deviceLastSeen != null) {
            trailing = Text(
              'Last seen ${_timeAgo(gState.deviceLastSeen!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.orange.shade700,
                fontSize: 11,
              ),
            );
          }
        } else {
          icon = Icons.cloud_done_rounded;
          label = 'Connected via WiFi';
          color = Colors.green;
          if (gState.deviceLastSeen != null) {
            trailing = Text(
              _timeAgo(gState.deviceLastSeen!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade600,
                fontSize: 11,
              ),
            );
          }
        }

      case GeyserMode.offline:
        final isBleConnecting =
            gState.bleStatus == BleConnectionStatus.connecting ||
            gState.bleStatus == BleConnectionStatus.discoveringServices ||
            gState.bleStatus == BleConnectionStatus.reconnecting;

        if (isBleConnecting) {
          icon = Icons.bluetooth_searching;
          label = 'Connecting…';
          color = Colors.orange;
          onTap = () => Navigator.of(context).push(DeviceScanPage.route());
        } else if (!bleState.isBluetoothOn) {
          icon = Icons.bluetooth_disabled;
          label = 'Bluetooth is off';
          color = Colors.grey;
          onTap = () => Navigator.of(context).push(DeviceScanPage.route());
        } else {
          icon = Icons.cloud_off_rounded;
          label = 'Not connected';
          color = Colors.grey;
          onTap = () => Navigator.of(context).push(DeviceScanPage.route());
        }
    }

    final banner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (trailing != null) trailing,
          if (onTap != null)
            Icon(
              Icons.chevron_right,
              size: 16,
              color: color.withValues(alpha: 0.6),
            ),
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: banner);
    }
    return banner;
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 30) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ── Custom timer row ─────────────────────────────────────────────────

class _CustomTimerRow extends StatelessWidget {
  const _CustomTimerRow({
    required this.timer,
    required this.onToggle,
    required this.onPickTime,
  });

  final GeyserTimer timer;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Tappable time button.
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: timer.enabled ? onPickTime : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: timer.enabled
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timer.timeFormatted,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: timer.enabled ? null : Colors.grey,
                    ),
                  ),
                  if (timer.enabled) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 14, color: Colors.grey.shade600),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Custom',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          Switch(
            value: timer.enabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}
