import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../data/firebase/config/geyser_config_repository.dart';
import '../../data/local/prefs_manager.dart';
import '../../data/telemetry/telemetry_recorder.dart';
import '../../di/locator.dart';
import '../../domain/auth/usecases/sign_out.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../../domain/geyser/entities/geyser_snapshot.dart';
import '../../domain/notifications/entities/device_notification.dart';
import '../ble/ble_connection_cubit.dart';
import '../ble/device_scan_page.dart';
import '../device/device_management_page.dart';
import '../device/device_registry_cubit.dart';
import '../geyser/geyser_control_cubit.dart';
import '../notifications/notification_service.dart';
import '../notifications/notifications_page.dart';
import '../shared/widgets/geyser_focal_card.dart';
import '../shared/widgets/stat_tile.dart';
import '../stats/device_stats_cubit.dart';
import '../stats/stats_card.dart';
import '../../domain/geyser/timer_presets.dart';

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
        title: BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
          builder: (context, regState) {
            if (!regState.isMultiDevice) {
              return const Text('GS Rework');
            }
            final device = regState.selectedDevice;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('GS Rework', style: TextStyle(fontSize: 16)),
                Text(
                  device?.nickname ?? 'Geyser',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            );
          },
        ),
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
          _UsageTab(),
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
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'Usage',
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

    // Tear down singletons that hold streams/subscriptions before
    // Firebase Auth signs out.  This prevents them from operating
    // on a signed-out auth context.
    await getIt<TelemetryRecorder>().stop();
    await getIt<NotificationService>().stop();
    await getIt<GeyserControlCubit>().resetForSignOut();
    context.read<BleConnectionCubit>().unpair();
    context.read<DeviceRegistryCubit>().clear();
    await getIt<PrefsManager>().clearDeviceData();

    await getIt<SignOut>().call();
  }
}


// ── Home tab ────────────────────────────────────────────────────────

class _HomeTab extends StatefulWidget {
  const _HomeTab();

  @override
  State<_HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<_HomeTab> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final registry = context.read<DeviceRegistryCubit>();
    _pageController = PageController(initialPage: registry.state.selectedIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    final registry = context.read<DeviceRegistryCubit>();
    registry.selectDevice(index);

    final device = registry.state.devices[index];
    context.read<GeyserControlCubit>().switchDevice(device.rtdbDeviceId);
    context.read<DeviceStatsCubit>().switchDevice(device.rtdbDeviceId);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
      builder: (context, regState) {
        if (!regState.isMultiDevice) {
          return const _SingleDeviceHome();
        }

        return Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: regState.devices.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  final device = regState.devices[index];
                  return _SingleDeviceHome(
                    deviceNicknameOverride: device.nickname,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8, top: 4),
              child: SmoothPageIndicator(
                controller: _pageController,
                count: regState.devices.length,
                effect: WormEffect(
                  dotHeight: 8,
                  dotWidth: 8,
                  spacing: 8,
                  activeDotColor: Theme.of(context).colorScheme.primary,
                  dotColor: Colors.grey.shade300,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The actual dashboard content for a single device.
///
/// Used directly when there's only one device, or as a page inside
/// the [PageView] when there are multiple devices.
class _SingleDeviceHome extends StatelessWidget {
  const _SingleDeviceHome({this.deviceNicknameOverride});

  final String? deviceNicknameOverride;

  @override
  Widget build(BuildContext context) {
    final bleState = context.watch<BleConnectionCubit>().state;
    final nickname = deviceNicknameOverride ??
        bleState.deviceNickname ??
        'Geyser';
    final geyserLabel = nickname.isNotEmpty ? nickname : 'Geyser';

    return BlocConsumer<GeyserControlCubit, GeyserControlState>(
      listenWhen: (prev, curr) =>
          prev.snapshot.isOn != curr.snapshot.isOn ||
          prev.error != curr.error,
      listener: (context, state) {
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

        final enabledTimers = snap.timers.where((t) => t.enabled).toList();
        final timerSubtitle = enabledTimers.isEmpty
            ? 'No timers active'
            : enabledTimers.map((t) => t.timeFormatted).join(' · ');

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
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
                onSensorOfflineTap: () =>
                    _showSensorOfflineInfo(context),
              ),
            ),
            const SizedBox(height: 12),

            const _ModeBanner(),
            const SizedBox(height: 12),

            Text(
              'Geyser Stats',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 10),

            StatTile(
              icon: Icons.thermostat_outlined,
              title: 'Temperature Range',
              subtitle: snap.isSensorOffline
                  ? 'Sensor offline — limits paused'
                  : '${snap.minTemp}°C – ${snap.maxTemp}°C'
                      '${snap.autoReheat ? ' (auto-reheat)' : ''}',
              onTap: snap.isSensorOffline
                  ? null
                  : () => _showTempLimitsDialog(context, snap),
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

            const SizedBox(height: 16),
            const StatsCard(),

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
        : defaultTimers();

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

  // ── Sensor offline info dialog ────────────────────────────────────

  void _showSensorOfflineInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.sensors_off, color: Colors.orange.shade600),
            const SizedBox(width: 8),
            const Text('Sensor Offline'),
          ],
        ),
        content: const Text(
          'The temperature sensor is not responding. '
          'This could mean the sensor cable is disconnected or damaged.\n\n'
          'While the sensor is offline:\n'
          '\u2022 Your geyser will continue to operate normally using '
          'its built-in thermostat\n'
          '\u2022 Temperature-based controls (limits, auto-reheat) '
          'are paused until the sensor recovers\n'
          '\u2022 The power toggle still works\n\n'
          'If this persists, check the sensor cable connection '
          'on the GeyserSwitch unit.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
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
          title: Row(
            children: [
              const Expanded(child: Text('Temperature Limits')),
              IconButton(
                icon: const Icon(Icons.health_and_safety_outlined, size: 22),
                tooltip: 'Water safety info',
                onPressed: () => _showLegionellaInfo(ctx),
              ),
            ],
          ),
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
                min: 5,
                max: 50,
                divisions: 45,
                value: min.toDouble().clamp(5, 50),
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
                min: 51,
                max: 65,
                divisions: 14,
                value: max.toDouble().clamp(51, 65),
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

  // ── Legionella safety info ────────────────────────────────────────

  void _showLegionellaInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.health_and_safety, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Water Safety', overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Why temperature matters',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Legionella bacteria thrive in stored water between '
                '20\u201345\u00B0C. Setting your geyser too low creates a health '
                'risk. Here\u2019s what happens at each range:',
              ),
              const SizedBox(height: 16),

              _infoRow(ctx, '< 20\u00B0C', 'Dormant \u2014 bacteria survive but don\u2019t multiply', Colors.blue),
              _infoRow(ctx, '20\u201345\u00B0C', 'Danger zone \u2014 rapid growth, especially 35\u201340\u00B0C', Colors.red),
              _infoRow(ctx, '50\u00B0C', 'Bacteria begin to die (slowly)', Colors.orange),
              _infoRow(ctx, '60\u00B0C', 'Rapid die-off \u2014 killed within minutes', Colors.green),
              _infoRow(ctx, '70\u00B0C+', 'Near-instant kill \u2014 thermal disinfection', Colors.green.shade800),

              const SizedBox(height: 16),
              Text(
                'Recommendations',
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                '\u2022  Keep your geyser at 60\u00B0C or above for safe stored water.\n'
                '\u2022  Never store water below 50\u00B0C for extended periods.\n'
                '\u2022  Water at the tap should reach 50\u201355\u00B0C within one minute.\n'
                '\u2022  In summer 50\u201355\u00B0C may be acceptable; in winter aim for 60\u201365\u00B0C.',
              ),

              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'South Africa: SANS 893 addresses Legionella control in water '
                  'systems. SANS 151 covers geyser insulation and heat loss. '
                  'SANS 241 (drinking water) does not currently mandate '
                  'Legionella testing \u2014 proper temperature management is your '
                  'primary defence.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String range, String desc, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5, right: 10),
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(
                    text: '$range  ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
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

// ── Usage tab ────────────────────────────────────────────────────────

class _UsageTab extends StatelessWidget {
  const _UsageTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bar_chart_rounded,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Usage History',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Daily and weekly energy charts coming soon.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
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
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Text(
          'Settings',
          style: theme.textTheme.titleMedium?.copyWith(
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
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Geyser Setup'),
          subtitle: BlocBuilder<DeviceStatsCubit, DeviceStatsState>(
            builder: (context, state) {
              final c = state.config;
              return Text(
                '${c.tankSize}L · ${c.elementKw.toStringAsFixed(1)} kW · '
                'R${c.costPerKwh.toStringAsFixed(2)}/kWh',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              );
            },
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showGeyserSetupDialog(context),
        ),
        const SizedBox(height: 20),
        BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
          builder: (context, regState) {
            final count = regState.devices.length;
            return ListTile(
              leading: const Icon(Icons.devices_other_outlined),
              title: const Text('Manage Devices'),
              subtitle: Text(
                count <= 1
                    ? '1 device registered'
                    : '$count devices registered',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context)
                  .push(DeviceManagementPage.route()),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showGeyserSetupDialog(BuildContext context) async {
    final configRepo = getIt<GeyserConfigRepository>();
    final statsCubit = context.read<DeviceStatsCubit>();
    final registry = context.read<DeviceRegistryCubit>();
    var config = statsCubit.state.config;
    final deviceId = registry.state.selectedRtdbId;

    final rateController = TextEditingController(
      text: config.costPerKwh.toStringAsFixed(2),
    );

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          return AlertDialog(
            title: const Text('Geyser Setup'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tank size and element are per-device. '
                    'Electricity rate and household size apply to your account.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 20),

                  DropdownButtonFormField<int>(
                    initialValue: config.tankSize,
                    decoration: const InputDecoration(
                      labelText: 'Tank size',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 100, child: Text('100 litres')),
                      DropdownMenuItem(value: 150, child: Text('150 litres')),
                      DropdownMenuItem(value: 200, child: Text('200 litres')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() => config = config.copyWith(tankSize: v));
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  DropdownButtonFormField<double>(
                    initialValue: config.elementKw,
                    decoration: const InputDecoration(
                      labelText: 'Element wattage',
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 2.0, child: Text('2.0 kW')),
                      DropdownMenuItem(value: 2.5, child: Text('2.5 kW')),
                      DropdownMenuItem(value: 3.0, child: Text('3.0 kW')),
                      DropdownMenuItem(value: 4.0, child: Text('4.0 kW')),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() => config = config.copyWith(elementKw: v));
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  TextFormField(
                    controller: rateController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Electricity rate (R/kWh)',
                      prefixText: 'R ',
                      isDense: true,
                      helperText:
                          'Eskom: ~R2.71 · City Power: ~R3.16\n'
                          'Cape Town: ~R3.91 · Durban: ~R2.24',
                      helperMaxLines: 2,
                      helperStyle: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  DropdownButtonFormField<int>(
                    initialValue: config.householdSize,
                    decoration: const InputDecoration(
                      labelText: 'Household size',
                      isDense: true,
                    ),
                    items: List.generate(
                      8,
                      (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1} ${i == 0 ? 'person' : 'people'}'),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(
                            () => config = config.copyWith(householdSize: v));
                      }
                    },
                  ),

                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Most SA homes have a 150L geyser with a 3 kW '
                          'element. Check the label on your geyser if unsure.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade500,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final parsed = double.tryParse(rateController.text);
                  if (parsed != null && parsed > 0) {
                    config = config.copyWith(costPerKwh: parsed);
                  }
                  if (deviceId != null) {
                    await configRepo.saveDeviceConfig(
                      deviceId,
                      config.deviceConfig,
                    );
                  }
                  await configRepo.saveUserConfig(config.userConfig);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    rateController.dispose();
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
      case NotificationType.sensorFail:
        return Colors.orange;
      case NotificationType.sensorRecover:
        return Colors.teal;
      case NotificationType.maxOnTimeout:
        return Colors.deepOrange;
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
      case NotificationType.sensorFail:
        return 'When the temperature sensor stops responding';
      case NotificationType.sensorRecover:
        return 'When the temperature sensor comes back online';
      case NotificationType.maxOnTimeout:
        return 'When geyser forced off after max continuous run';
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
