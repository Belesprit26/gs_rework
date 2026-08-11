import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../core/debug/debug_log.dart';
import '../../data/local/prefs_manager.dart';
import '../../di/locator.dart';
import '../../domain/geyser/entities/geyser_snapshot.dart';
import '../../domain/geyser/temp_limits.dart';
import '../../domain/notifications/repositories/notification_repository.dart';
import '../ble/ble_connection_cubit.dart';
import '../device/device_registry_cubit.dart';
import '../geyser/geyser_control_cubit.dart';
import '../auth/widgets/neu_auth_widgets.dart';
import '../notifications/notification_service.dart';
import '../notifications/notifications_page.dart';
import '../shared/feedback/app_snack.dart';
import '../shared/feedback/haptics.dart';
import 'connectivity_badge.dart';
import '../settings/settings_tab.dart';
import '../shared/widgets/geyser_focal_card.dart';
import '../shared/widgets/neu/neu.dart';
import '../shared/widgets/neu/neu_bottom_nav.dart';
import '../shared/widgets/neu/neu_slider.dart';
import '../shared/widgets/run_limit_chips.dart';
import '../stats/device_stats_cubit.dart';
import '../theme/app_colors.dart';
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
        centerTitle: false,
        // The bar takes the neu ground so the badge's plinth blends
        // exactly as it does on the auth screen — the soft-UI disc only
        // melts into a background of its own color.
        backgroundColor: AppColors.neuBase,
        title: BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
          builder: (context, regState) {
            // The brand badge replaces the "GS Rework" wordmark — same
            // widget as the auth screen, sized for the app bar.
            if (!regState.isMultiDevice) {
              return const Align(
                alignment: Alignment.centerLeft,
                child: _LogoHubButton(),
              );
            }
            final device = regState.selectedDevice;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _LogoHubButton(),
                const SizedBox(width: 12),
                Text(
                  device?.nickname ?? 'Geyser',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            );
          },
        ),
        actions: const [
          _NotificationBell(),
          SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: const [
          _HomeTab(),
          _UsageTab(),
          SettingsTab(),
        ],
      ),
      bottomNavigationBar: NeuBottomNav(
        selectedIndex: _currentTab,
        onSelected: (i) => setState(() => _currentTab = i),
        items: const [
          NeuNavItem(
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard_rounded,
            label: 'Home',
          ),
          NeuNavItem(
            icon: Icons.bar_chart_outlined,
            selectedIcon: Icons.bar_chart_rounded,
            label: 'Usage',
          ),
          NeuNavItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings_rounded,
            label: 'Settings',
          ),
        ],
      ),
    );
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

  /// True while a programmatic animateToPage is running, so the
  /// intermediate onPageChanged callbacks it fires don't get mistaken
  /// for user swipes and re-drive selection through every page crossed.
  bool _animating = false;

  /// Set when a selection arrives while the PageView is detached (the
  /// single→multi-device transition); consumed once it attaches.
  int? _pendingPageSync;

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
    // Ignore boundaries crossed during a programmatic animate — only a
    // real user swipe should drive selection. Otherwise report it: the
    // DeviceSelectionCoordinator fans it out to the stats + geyser
    // cubits, so a swipe and a Settings switch take the same path.
    if (_animating) return;
    context.read<DeviceRegistryCubit>().selectDevice(index);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DeviceRegistryCubit, DeviceRegistryState>(
      // Follow selection changes made ELSEWHERE (e.g. the Settings
      // switcher): move the PageView to match. Guarded against the
      // swipe's own echo — animating to the page we're already on is a
      // no-op we skip so we don't fight the user's drag.
      listener: (context, regState) {
        if (!_pageController.hasClients) {
          // View not attached yet (still on the single-device layout
          // when a 2nd device was added). Land there once it attaches.
          _pendingPageSync = regState.selectedIndex;
          return;
        }
        final current = _pageController.page?.round();
        if (current != null && current != regState.selectedIndex) {
          _animating = true;
          _pageController
              .animateToPage(
                regState.selectedIndex,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              )
              .whenComplete(() => _animating = false);
        }
      },
      builder: (context, regState) {
        // First-run (or last device removed): nothing to show a
        // connection or reading for — a pairing CTA carries the
        // instruction and the app-bar logo breathes to point the way.
        if (regState.devices.isEmpty) {
          return const _NoDeviceHome();
        }
        if (!regState.isMultiDevice) {
          return const _SingleDeviceHome();
        }

        // Reconcile a selection that arrived while detached: jump the
        // freshly-attached PageView onto it (instant, not animated —
        // it's a correction, not a user action).
        if (_pendingPageSync != null) {
          final target = _pendingPageSync!;
          _pendingPageSync = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_pageController.hasClients) return;
            if (target < regState.devices.length &&
                _pageController.page?.round() != target) {
              _pageController.jumpToPage(target);
            }
          });
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

/// First-run home: no devices registered yet, so no focal card, no rail,
/// no stats — one clear "pair it" card that opens the connection hub
/// (the same sheet the breathing app-bar logo opens).
class _NoDeviceHome extends StatelessWidget {
  const _NoDeviceHome();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        const SizedBox(height: 28),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: NeuPanel(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
            color: AppColors.surface,
            child: Column(
              children: [
                const AuthLogoBadge(
                    size: 72, plinthColor: AppColors.surface),
                const SizedBox(height: 18),
                const Text(
                  'Pair your GeyserSwitch',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Connect over Bluetooth to set up your geyser — '
                  'schedules, temperature and savings start here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: 20),
                NeuButton(
                  label: 'Get started',
                  primary: true,
                  onPressed: () {
                    Haptics.tap();
                    showConnectivitySheet(context);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
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
        final error = state.error;
        if (error != null) {
          // Raw error text is for the log, never the UI (UX_POLISH_PLAN §A).
          debugLog('Dashboard', 'Command error: $error');
          // A device we can't reach is a condition, not a fault — amber
          // warning. Anything else is a genuine failure.
          final unreachable =
              error.contains('timed out') || error.contains('offline');
          showAppSnack(
            context,
            type: unreachable ? AppSnackType.warning : AppSnackType.error,
            message: unreachable
                ? "Couldn't reach the geyser — it looks offline. "
                    'Nothing was changed.'
                : "That didn't go through. Try again in a moment.",
          );
        }
      },
      builder: (context, state) {
        final snap = state.snapshot;
        final deviceId =
            context.read<DeviceRegistryCubit>().state.selectedRtdbId;
        final isTimeMode = deviceId != null &&
            getIt<PrefsManager>().isTimeHeatMode(deviceId);

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            if (bleState.isOwnerLocked) const _OwnerLockedBanner(),
            _FocalWithAlertRail(
              deviceId: deviceId,
              name: geyserLabel,
              snapshot: snap,
              isLoading: state.isLoading,
              isBusy: state.isBusy,
              onSensorOfflineTap: () => _showSensorOfflineInfo(context),
            ),
            // The old mode banner's job now lives in the rail's
            // connectivity badge + its tap sheet.
            const SizedBox(height: 12),
            if (!snap.deviceClockValid) ...[
              _ClockLostBanner(intervalMode: snap.intervalModeActive),
              const SizedBox(height: 12),
            ],

            // Savings summary + quick-glance tiles.
            const _SavingsCard(),
            const SizedBox(height: 14),
            _AtAGlanceGrid(
              snapshot: snap,
              isTimeMode: isTimeMode,
              onOpenTimers: () => _showTimerSettingsDialog(context, snap),
              // Always tappable: limits are only PAUSED while the sensor
              // is offline, and the user may well want to set them up
              // ready for it coming back. The dialog says so itself.
              onOpenTempRange: () => _showTempLimitsDialog(context, snap),
            ),
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
            backgroundColor: AppColors.neuBase,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
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
              NeuButton(
                label: 'Cancel',
                onPressed: () => Navigator.pop(ctx),
              ),
              NeuButton(
                label: 'Save',
                primary: true,
                onPressed: () {
                  Haptics.commit();
                  cubit.setTimers(timers);
                  Navigator.pop(ctx);
                  // Page context, not ctx — the dialog just popped.
                  Haptics.success();
                  showAppSnack(context,
                      type: AppSnackType.success, message: 'Timers saved');
                },
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
    final prefs = getIt<PrefsManager>();
    final deviceId = context.read<DeviceRegistryCubit>().state.selectedRtdbId;

    // Everything is staged locally and written only on Save, so Cancel is
    // honest for the run-limit chips too (unlike the always-live chips in
    // Settings).
    var min = snap.minTemp;
    var max = snap.maxTemp;
    var autoReheat = snap.autoReheat;
    var maxOn = snap.maxOnMinutes;

    // Open in whatever mode this device was last left in. In time mode the
    // device holds the parked ceiling / auto-reheat-off values; show the
    // user's remembered temperature-mode limits on the sliders instead, so
    // flipping back to "Heat to a temperature" restores what they had.
    var timeMode = false;
    if (deviceId != null && prefs.isTimeHeatMode(deviceId)) {
      timeMode = true;
      max = prefs.savedHeatMax(deviceId) ?? snap.maxTemp;
      autoReheat = prefs.savedHeatAutoReheat(deviceId) ?? snap.autoReheat;
    }
    final startedInTime = timeMode;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.neuBase,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              const Expanded(child: Text('Temperature')),
              IconButton(
                icon: const Icon(Icons.health_and_safety_outlined, size: 22),
                tooltip: 'Water safety info',
                onPressed: () => _showLegionellaInfo(ctx),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeatModeToggle(
                  timeMode: timeMode,
                  onChanged: (v) => setDialogState(() => timeMode = v),
                ),
                const SizedBox(height: 16),

                // Reachable while the sensor is offline on purpose — the
                // ceiling is paused, not invalid, and can be set up ready
                // for it recovering.
                if (snap.isSensorOffline) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.sensors_off,
                            size: 18, color: Colors.orange.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sensor offline — the temperature ceiling is '
                            'paused and resumes automatically once it '
                            'reconnects.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (!timeMode) ...[
                  // ── Heat to a temperature ──────────────────────────
                  Row(
                    children: [
                      const Expanded(child: Text('Min')),
                      Text('$min°C'),
                    ],
                  ),
                  SliderTheme(
                    data: neuSliderTheme(ctx, accent: AppColors.primary),
                    child: Slider(
                      min: 5,
                      max: 50,
                      divisions: 45,
                      value: min.toDouble().clamp(5, 50),
                      onChanged: (v) => setDialogState(() => min = v.round()),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Expanded(child: Text('Max')),
                      Text('$max°C'),
                    ],
                  ),
                  SliderTheme(
                    data: neuSliderTheme(ctx, accent: AppColors.rampOrange),
                    child: Slider(
                      min: tempMaxFloor.toDouble(),
                      max: tempMaxCeil.toDouble(),
                      divisions: tempMaxCeil - tempMaxFloor,
                      value:
                          max.toDouble().clamp(tempMaxFloor, tempMaxCeil).toDouble(),
                      onChanged: (v) => setDialogState(() => max = v.round()),
                    ),
                  ),
                  const Divider(height: 24),
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
                              style:
                                  Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                        color: Colors.grey.shade600,
                                      ),
                            ),
                          ],
                        ),
                      ),
                      NeuSwitch(
                        value: autoReheat,
                        onChanged: (v) => setDialogState(() => autoReheat = v),
                      ),
                    ],
                  ),
                ] else ...[
                  // ── Heat for a time ────────────────────────────────
                  Text(
                    'Save the most with single-cycle heat-ups (Heat to a Temperature), or run a '
                    'longer continuous session for long baths and a full '
                    'house right here.',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 14),
                  RunLimitChips(
                    currentMinutes: maxOn,
                    onSelect: (m) => setDialogState(() => maxOn = m),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline,
                          size: 15, color: Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Starts from your timers (manual switch-on), and '
                          'keeps running for the duration',
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                                fontSize: 11,
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            NeuButton(
              label: 'Cancel',
              onPressed: () => Navigator.pop(ctx),
            ),
            NeuButton(
              label: 'Save',
              primary: true,
              onPressed: () async {
                Haptics.commit();
                if (timeMode) {
                  // Remember the temperature-mode limits, then park the
                  // ceiling at its max + auto-reheat off and lean on the
                  // timers + run limit.
                  if (deviceId != null) {
                    await prefs.enableTimeHeatMode(
                      deviceId,
                      savedMax: max,
                      savedAutoReheat: autoReheat,
                    );
                  }
                  cubit.setTempLimits(
                      min: min, max: tempMaxCeil, autoReheat: false);
                  cubit.setMaxOnTimer(maxOn);
                } else {
                  if (deviceId != null && startedInTime) {
                    await prefs.disableTimeHeatMode(deviceId);
                  }
                  cubit.setTempLimits(
                    min: min,
                    max: max,
                    autoReheat: autoReheat,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
                // Page context — survives the pop; guarded because of the
                // await above.
                if (context.mounted) {
                  Haptics.success();
                  showAppSnack(context,
                      type: AppSnackType.success,
                      message: timeMode
                          ? 'Heat-for-a-time saved'
                          : 'Temperature range saved');
                }
              },
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Time label (non-editable for presets) — inset + bold when
          // active, raised + dull when off (see _TimeChip).
          _TimeChip(
            enabled: timer.enabled,
            child: Text(
              timer.timeFormatted,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: timer.enabled ? AppColors.ink : AppColors.muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _offPeakLabel(timer.hour),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
          const Spacer(),
          NeuSwitch(
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

/// Shared time-chip treatment for both preset and custom timer rows.
///
/// Enabled/active timers read as embedded into the surface (debossed +
/// bold text); disabled timers recede, protruding slightly with dull
/// text — the inverse of the usual "raised = active" convention, chosen
/// deliberately so the active schedule looks fixed/committed.
class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (enabled) return NeuInset(child: child);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.neuBase,
        borderRadius: BorderRadius.circular(10),
        boxShadow: neuRaisedShadows(distance: 3, blur: 6),
      ),
      child: child,
    );
  }
}

// ── Logo hub button ───────────────────────────────────────────────────
//
// The app-bar brand badge is a real button: press = momentary inset
// ("active is inset"), tap = light haptic + the connection sheet — the
// same surface the rail badge opens, so connection + provisioning are
// reachable from every tab. Phase D of UX_POLISH_PLAN.

class _LogoHubButton extends StatefulWidget {
  const _LogoHubButton();

  @override
  State<_LogoHubButton> createState() => _LogoHubButtonState();
}

class _LogoHubButtonState extends State<_LogoHubButton>
    with SingleTickerProviderStateMixin {
  bool _down = false;
  late final AnimationController _breathe;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  void _open() {
    Haptics.tap();
    showConnectivitySheet(context);
  }

  @override
  Widget build(BuildContext context) {
    // First-run beacon: while no device is registered, the logo breathes
    // a teal halo (the connecting-badge grammar) to point at the hub —
    // and returns if the last device is ever removed.
    final noDevices =
        context.watch<DeviceRegistryCubit>().state.devices.isEmpty;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (noDevices && !reduceMotion) {
      if (!_breathe.isAnimating) _breathe.repeat(reverse: true);
    } else {
      if (_breathe.isAnimating) _breathe.stop();
    }

    return Semantics(
      button: true,
      label: 'Connection hub',
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: _open,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down ? 0.94 : 1,
          duration: const Duration(milliseconds: 110),
          child: AnimatedBuilder(
            animation: _breathe,
            builder: (context, child) {
              final halo = noDevices
                  ? AppColors.primary.withValues(
                      alpha: reduceMotion
                          ? 0.30
                          : 0.15 + 0.25 * _breathe.value)
                  : null;
              return Container(
                decoration: halo == null
                    ? null
                    : BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: halo,
                            blurRadius: 10,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                child: child,
              );
            },
            child: AuthLogoBadge(size: 44, pressed: _down),
          ),
        ),
      ),
    );
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

/// Compact duration for run-time-remaining copy ("2 h 15 m", "45 m").
String _formatDuration(int seconds) {
  if (seconds < 60) return '<1 m';
  final totalMinutes = seconds ~/ 60;
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return '$m m';
  if (m == 0) return '$h h';
  return '$h h $m m';
}

// ── Focal card + hanging-alert rail ───────────────────────────────────
//
// Persistent hardware hazards hang in the 46 px gutter beside the focal
// card — never inside it — as small neu badges, stacked top-down by
// severity. Purely additive: the rail only occupies the gutter that was
// already empty, so a device with nothing wrong renders exactly as before.
//
// Leak is the first (and, for now, only) badge. Its active state is
// derived app-side from the event pair — an EVT_LEAK not yet followed by
// EVT_LEAK_CLEAR (see NotificationRepository.hasActiveLeak) — and refreshes
// on every NotificationService.changes tick, so a leak arriving by BLE or
// FCM lights the rail without a manual reload.

/// The leak's identity colour — the ramp's water blue.
const Color _kLeakColor = AppColors.rampBlue;

class _FocalWithAlertRail extends StatefulWidget {
  const _FocalWithAlertRail({
    required this.deviceId,
    required this.name,
    required this.snapshot,
    required this.isLoading,
    required this.isBusy,
    required this.onSensorOfflineTap,
  });

  final String? deviceId;
  final String name;
  final GeyserSnapshot snapshot;
  final bool isLoading;
  final bool isBusy;
  final VoidCallback onSensorOfflineTap;

  @override
  State<_FocalWithAlertRail> createState() => _FocalWithAlertRailState();
}

class _FocalWithAlertRailState extends State<_FocalWithAlertRail> {
  late final NotificationService _service;
  late final NotificationRepository _repo;
  StreamSubscription<void>? _sub;

  bool _leakActive = false;

  /// Shown when the user taps the power toggle while a leak is latched —
  /// the toggle is gated and this points them to the badge instead.
  bool _showNudge = false;

  @override
  void initState() {
    super.initState();
    _service = getIt<NotificationService>();
    _repo = getIt<NotificationRepository>();
    _sub = _service.changes.listen((_) => _refreshLeak());
    _refreshLeak();
  }

  @override
  void didUpdateWidget(_FocalWithAlertRail old) {
    super.didUpdateWidget(old);
    if (old.deviceId != widget.deviceId) {
      _showNudge = false;
      _refreshLeak();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _refreshLeak() async {
    final id = widget.deviceId;
    final active = id == null ? false : await _repo.hasActiveLeak(id);
    if (!mounted || active == _leakActive) return;
    setState(() {
      _leakActive = active;
      // A cleared leak drops any lingering gate nudge.
      if (!active) _showNudge = false;
    });
  }

  void _onTogglePressed() {
    // Gate turning ON while a leak is latched: don't send the command,
    // surface the nudge + let the badge draw the eye. Turning OFF (or
    // acting once already overridden/on) always passes straight through.
    if (_leakActive && !widget.snapshot.isOn) {
      Haptics.blocked();
      setState(() => _showNudge = true);
      return;
    }
    Haptics.commit();
    context.read<GeyserControlCubit>().toggleGeyser();
  }

  void _openSheet() {
    showLeakDetailSheet(
      context,
      canOverride: !widget.snapshot.isOn,
      onOverride: () => context.read<GeyserControlCubit>().toggleGeyser(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 46,
              // Connectivity pinned top (a stable anchor that never
              // shifts); hazard badges stack beneath it.
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  children: [
                    ConnectivityBadge(deviceId: widget.deviceId),
                    if (_leakActive) ...[
                      const SizedBox(height: 12),
                      _LeakBadge(onTap: _openSheet),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: GeyserFocalCard(
                name: widget.name,
                isOn: widget.snapshot.isOn,
                temperature: widget.snapshot.temperature,
                isLoading: widget.isLoading,
                isBusy: widget.isBusy,
                onToggle: _onTogglePressed,
                onSensorOfflineTap: widget.onSensorOfflineTap,
              ),
            ),
            const SizedBox(width: 46),
          ],
        ),
        // Only while still off — once it's on (e.g. after an override) the
        // "before switching on" prompt is stale, so it hides until the
        // geyser is off again.
        if (_showNudge && _leakActive && !widget.snapshot.isOn)
          Padding(
            padding: const EdgeInsets.fromLTRB(46, 12, 46, 0),
            child: _LeakNudge(onReview: _openSheet),
          ),
      ],
    );
  }
}

/// The hanging leak badge: a 40 px neu circle with the blue drop and a
/// tight blue halo that gently breathes. Tap opens the detail sheet.
class _LeakBadge extends StatefulWidget {
  const _LeakBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_LeakBadge> createState() => _LeakBadgeState();
}

class _LeakBadgeState extends State<_LeakBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: 'Water leak detected, critical. Tap for details.',
      child: GestureDetector(
        onTap: () {
          Haptics.tap();
          widget.onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final t = reduce ? 0.5 : _pulse.value;
            return Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neuBase,
                boxShadow: [
                  ...neuRaisedShadows(distance: 3, blur: 7),
                  BoxShadow(
                    color: _kLeakColor.withValues(alpha: 0.28 + 0.22 * t),
                    blurRadius: 7,
                    spreadRadius: 0.5 + 0.5 * t,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: const Icon(Icons.water_drop, size: 20, color: _kLeakColor),
        ),
      ),
    );
  }
}

/// Inline gate feedback shown under the card when a leak-latched toggle is
/// tapped. Whole card is tappable to open the detail sheet.
class _LeakNudge extends StatelessWidget {
  const _LeakNudge({required this.onReview});

  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onReview,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: neuRaisedShadows(distance: 4, blur: 12),
          border: const Border(
            left: BorderSide(color: _kLeakColor, width: 3),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.water_drop, size: 18, color: _kLeakColor),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Turned off after a water leak. Tap to review before '
                'switching on.',
                style: TextStyle(fontSize: 12.5, color: AppColors.ink),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}

/// The leak detail sheet: what happened, why it matters, what to do, and
/// (while still off) the deliberate override. Reached only by tapping the
/// badge or the gate nudge — never by the casual power toggle.
Future<void> showLeakDetailSheet(
  BuildContext context, {
  required bool canOverride,
  required VoidCallback onOverride,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.paper,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.neuBase,
                      boxShadow: [
                        ...neuRaisedShadows(distance: 4, blur: 10),
                        BoxShadow(
                          color: _kLeakColor.withValues(alpha: 0.32),
                          blurRadius: 9,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.water_drop,
                        size: 26, color: _kLeakColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          canOverride ? 'CRITICAL · STILL WET' : 'CRITICAL',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: _kLeakColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Water leak detected',
                          style: Theme.of(sheetContext)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'GeyserSwitch sensed water near the geyser and cut the power '
                'automatically. It stays off until you turn it back on — the '
                'schedule and auto-reheat can’t re-energise it while it’s wet.',
                style: TextStyle(
                    fontSize: 14.5, height: 1.4, color: AppColors.inkSecondary),
              ),
              const SizedBox(height: 16),
              _LeakSteps(),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: NeuButton(
                      label: 'Dismiss',
                      onPressed: () => Navigator.of(sheetContext).pop(),
                    ),
                  ),
                  if (canOverride) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _LeakOverrideButton(
                        onPressed: () {
                          // The deliberate, informed override — a commit.
                          Haptics.commit();
                          Navigator.of(sheetContext).pop();
                          onOverride();
                        },
                      ),
                    ),
                  ],
                ],
              ),
              if (canOverride) ...[
                const SizedBox(height: 12),
                const Text(
                  'Turning it back on resumes normal heating. The alert stays '
                  'until the sensor reports dry.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: AppColors.muted),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _LeakSteps extends StatelessWidget {
  static const _steps = <String>[
    'Close the water supply to the geyser — the cut-off stops the element, '
        'not the water.',
    'Check for pooling and call a plumber if you find any.',
    'Dry the sensor area — the alert clears on its own once it’s dry.',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: neuRaisedShadows(distance: 3, blur: 8),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(
                        top: BorderSide(color: AppColors.hairline),
                      ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kLeakColor,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _steps[i],
                      style: const TextStyle(
                          fontSize: 13.5, height: 1.35, color: AppColors.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The blue filled override — kept visually distinct from [NeuButton] so
/// the deliberate action reads as deliberate.
class _LeakOverrideButton extends StatelessWidget {
  const _LeakOverrideButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _kLeakColor,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: _kLeakColor.withValues(alpha: 0.35),
              offset: const Offset(3, 3),
              blurRadius: 8,
            ),
          ],
        ),
        child: const Text(
          'Turn back on anyway',
          textAlign: TextAlign.center,
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }
}

// ── Device clock lost banner ──────────────────────────────────────────
//
// The device's schedule is wall-clock based, so without a usable clock
// it cannot run. Firmware ≥ 0.7.0 keeps heating on a free-running
// interval at the same daily duty meanwhile. The fix is automatic — the
// app pushes the phone's time on every Bluetooth connection — so this
// explains what happened rather than asking the user to do anything.

class _ClockLostBanner extends StatelessWidget {
  const _ClockLostBanner({required this.intervalMode});

  final bool intervalMode;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.schedule_outlined,
              size: 20, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  intervalMode
                      ? 'Schedule paused — running on a backup timer'
                      : 'Device clock not set',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.orange.shade900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Staying connected here sets the time again and '
                  'restores your timers.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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

    final timeChild = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timer.timeFormatted,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: timer.enabled ? AppColors.ink : AppColors.muted,
          ),
        ),
        if (timer.enabled) ...[
          const SizedBox(width: 4),
          const Icon(Icons.edit, size: 14, color: AppColors.inkSecondary),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Tappable time button — inset + bold when active, raised +
          // dull when off (see _TimeChip).
          GestureDetector(
            onTap: timer.enabled ? onPickTime : null,
            child: _TimeChip(enabled: timer.enabled, child: timeChild),
          ),
          const SizedBox(width: 8),
          Text(
            'Custom',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.inkSecondary,
            ),
          ),
          const Spacer(),
          NeuSwitch(
            value: timer.enabled,
            onChanged: onToggle,
          ),
        ],
      ),
    );
  }
}

/// Shown when connected over BLE to a geyser this phone isn't
/// authorized to control (owner-lock). Reads and remote/cloud control
/// still work; only local BLE commands are blocked.
class _OwnerLockedBanner extends StatelessWidget {
  const _OwnerLockedBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, color: cs.onErrorContainer, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'This GeyserSwitch is registered to another account. '
              'Sign in with the owning account, or hold the device button '
              '10s to factory-reset and claim it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onErrorContainer,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Savings summary card ──────────────────────────────────────────────
//
// "What you've saved" — a Rands-first view of DeviceStatsCubit. The Day
// tab is backed by real data (runtime × element kW × rate, compared to
// the SA baseline for the tank size, all from DeviceStatsState). Week and
// Month are placeholders until a stats-range fetch is added — kept as a
// separate increment rather than bundled here.
class _SavingsCard extends StatefulWidget {
  const _SavingsCard();

  @override
  State<_SavingsCard> createState() => _SavingsCardState();
}

class _SavingsCardState extends State<_SavingsCard> {
  int _period = 0; // 0 = Day, 1 = Week, 2 = Month

  // Brand accent from the logo arc: cool = the (efficient) amount you
  // actually spent, warm = the "usual" bill you avoided.
  static const _cool = AppColors.rampTeal;
  static const _warm = AppColors.rampOrange;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                "What you've saved",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _PeriodSegmented(
              index: _period,
              onChanged: (i) => setState(() => _period = i),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SoftCard(
          padding: const EdgeInsets.all(16),
          child: _period == 0 ? _buildDay(context) : _buildComingSoon(context),
        ),
      ],
    );
  }

  Widget _buildComingSoon(BuildContext context) {
    final theme = Theme.of(context);
    final label = _period == 1 ? 'Weekly' : 'Monthly';
    return SizedBox(
      height: 96,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insights_outlined, color: AppColors.muted),
            const SizedBox(height: 8),
            Text(
              '$label totals are coming soon',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.inkSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Showing today for now',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDay(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<DeviceStatsCubit, DeviceStatsState>(
      builder: (context, state) {
        if (!state.hasData) {
          return SizedBox(
            height: 96,
            child: Center(
              child: Text(
                'No usage yet today — your savings will\n'
                'show here once the geyser runs.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ),
          );
        }

        final rate = state.config.costPerKwh;
        final spent = state.actualCost;
        final usual = state.baselineKwh * rate;
        final saved = state.savedCost;
        final spentFrac = usual > 0 ? (spent / usual).clamp(0.0, 1.0) : 1.0;
        final savedNow = saved > 0.005;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              savedNow
                  ? "Today you've saved"
                  : 'About the same as usual today',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.inkSecondary,
              ),
            ),
            if (savedNow) ...[
              const SizedBox(height: 4),
              Text(
                'R${saved.toStringAsFixed(2)}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.save,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'by heating smart instead of leaving it on',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.muted,
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Money thermometer: the slice of the "usual" bill you used.
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    Expanded(
                      flex: (spentFrac * 1000).round().clamp(1, 1000),
                      child: Container(color: _cool),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: ((1 - spentFrac) * 1000).round().clamp(1, 1000),
                      child: Container(color: _warm),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _legend(
                    context, 'R${spent.toStringAsFixed(0)} you spent', _cool),
                _legend(context, 'R${usual.toStringAsFixed(0)} usual', _warm),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _legend(BuildContext context, String text, Color color) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}

/// Compact Day / Week / Month segmented control.
class _PeriodSegmented extends StatelessWidget {
  const _PeriodSegmented({required this.index, required this.onChanged});

  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['Day', 'Week', 'Month'];
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(labels.length, (i) {
          final active = i == index;
          return GestureDetector(
            onTap: () {
              if (!active) Haptics.select();
              onChanged(i);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: active ? AppColors.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: active
                    ? const [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                labels[i],
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: active ? AppColors.ink : AppColors.inkSecondary,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// The segmented "Heat to a temperature | Heat for a time" switch at the
/// top of the temperature dialog. The active side is a teal pill, matching
/// the run-limit chips shown below it in time mode.
class _HeatModeToggle extends StatelessWidget {
  const _HeatModeToggle({required this.timeMode, required this.onChanged});

  final bool timeMode;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline, width: 1.5),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _segment(
                'Heat to a temperature',
                active: !timeMode,
                onTap: () {
                  if (timeMode) Haptics.select();
                  onChanged(false);
                },
              ),
            ),
            Expanded(
              child: _segment(
                'Heat for a time',
                active: timeMode,
                onTap: () {
                  if (!timeMode) Haptics.select();
                  onChanged(true);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    String label, {
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: active ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : AppColors.inkSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ── At a glance grid ──────────────────────────────────────────────────
//
// Four quick-status tiles. Next timer + temperature come from the geyser
// snapshot; heated-today + cycles from DeviceStatsCubit. Next-timer and
// temperature tiles open their respective settings dialogs on tap.
class _AtAGlanceGrid extends StatelessWidget {
  const _AtAGlanceGrid({
    required this.snapshot,
    this.isTimeMode = false,
    this.onOpenTimers,
    this.onOpenTempRange,
  });

  final GeyserSnapshot snapshot;

  /// When the geyser is in "Heat for a time" mode the temperature tile
  /// shows the run duration rather than a min–max band that no longer
  /// governs it.
  final bool isTimeMode;

  /// Opens the timer-settings dialog (Next timer tile).
  final VoidCallback? onOpenTimers;

  /// Opens the temperature-limits dialog (Temperature tile). Null disables
  /// the tap — e.g. while the sensor is offline and limits are paused.
  final VoidCallback? onOpenTempRange;

  /// "Timed · 2h" style label for the temperature tile in time mode.
  String _timedTempValue(int minutes) {
    if (minutes <= 0) return 'Timed';
    if (minutes < 60) return 'Timed · ${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? 'Timed · ${h}h' : 'Timed · ${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = _nextTimer(snapshot.timers);
    final activeCount = snapshot.timers.where((t) => t.enabled).length;

    // While the geyser is on, how long it has left is more useful than
    // the timer count. Applies to every switch-on — schedule, manual or
    // remote — so the wording stays generic.
    final remaining = snapshot.runTimeRemainingSeconds;
    final String timerFootnote;
    if (snapshot.isOn && remaining != null) {
      timerFootnote = 'Running · ${_formatDuration(remaining)} left';
    } else if (snapshot.isOn && snapshot.maxOnMinutes <= 0) {
      timerFootnote = 'Running · no run limit set';
    } else if (snapshot.isOn) {
      // A limit exists but we have no run-status reading to age from
      // (remote mode, or firmware without 0x0F) — say so rather than
      // invent a countdown.
      timerFootnote = 'Running';
    } else {
      timerFootnote = 'Active timers: $activeCount';
    }

    final tempValue = isTimeMode
        ? _timedTempValue(snapshot.maxOnMinutes)
        : '${snapshot.minTemp}°–${snapshot.maxTemp}°C';
    final tempFootnote = snapshot.isSensorOffline
        ? 'Limits paused · sensor offline'
        : isTimeMode
            ? 'Heats for a set time'
            : (snapshot.autoReheat ? 'Auto-reheat on' : 'Auto-reheat off');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'At a glance',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        BlocBuilder<DeviceStatsCubit, DeviceStatsState>(
          builder: (context, stats) {
            return Column(
              children: [
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _GlanceTile(
                          label: 'Next timer',
                          value: next?.$1 ?? 'None set',
                          hint: next?.$2,
                          footnote: timerFootnote,
                          onTap: onOpenTimers,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _GlanceTile(
                          label: 'Temperature',
                          value: tempValue,
                          footnote: tempFootnote,
                          onTap: onOpenTempRange,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _GlanceTile(
                        label: 'Heated today',
                        value: _fmtRuntime(stats.stats.runtimeSeconds),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _GlanceTile(
                        label: 'Cycles',
                        value: '${stats.stats.cycleCount}',
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// (timeLabel, hint) for the soonest enabled timer, wrapping to
  /// tomorrow; null when nothing is scheduled.
  (String, String?)? _nextTimer(List<dynamic> timers) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    int? bestDelta;
    dynamic best;
    for (final t in timers) {
      if (t.enabled != true) continue;
      final mins = (t.hour as int) * 60 + (t.minute as int);
      var delta = mins - nowMin;
      if (delta < 0) delta += 24 * 60;
      if (bestDelta == null || delta < bestDelta) {
        bestDelta = delta;
        best = t;
      }
    }
    if (best == null) return null;
    final h = (best.hour as int).toString().padLeft(2, '0');
    final m = (best.minute as int).toString().padLeft(2, '0');
    final hint = (best.isPreset == true) ? 'off-peak' : 'custom';
    return ('$h:$m', hint);
  }

  static String _fmtRuntime(int seconds) {
    if (seconds <= 0) return '0m';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }
}

class _GlanceTile extends StatelessWidget {
  const _GlanceTile({
    required this.label,
    required this.value,
    this.hint,
    this.footnote,
    this.onTap,
  });

  final String label;
  final String value;

  /// Small muted qualifier shown inline after [value].
  final String? hint;

  /// Secondary line shown below [value] (e.g. auto-reheat state).
  final String? footnote;

  /// When non-null the tile is tappable and shows a chevron affordance.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tappable = onTap != null;

    final card = SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      borderRadius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              if (tappable)
                const Icon(
                  Icons.chevron_right,
                  size: 15,
                  color: AppColors.muted,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (hint != null) ...[
                const SizedBox(width: 5),
                Text(
                  hint!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.muted,
                  ),
                ),
              ],
            ],
          ),
          if (footnote != null) ...[
            const SizedBox(height: 4),
            Text(
              footnote!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.muted,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
    );

    if (!tappable) return card;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }
}
