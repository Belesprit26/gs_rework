import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/firebase/config/geyser_config_repository.dart';
import '../../data/firebase/fcm/push_notification_manager.dart';
import '../../data/local/prefs_manager.dart';
import '../../data/telemetry/telemetry_recorder.dart';
import '../../di/locator.dart';
import '../../domain/auth/repositories/auth_repository.dart';
import '../../domain/auth/usecases/sign_out.dart';
import '../../domain/notifications/entities/device_notification.dart';
import '../../domain/notifications/repositories/notification_repository.dart';
import '../../domain/telemetry/repositories/telemetry_repository.dart';
import '../ble/ble_connection_cubit.dart';
import '../device/device_management_page.dart';
import '../device/device_registry_cubit.dart';
import '../geyser/geyser_control_cubit.dart';
import '../notifications/notification_priming_sheet.dart';
import '../notifications/notification_service.dart';
import '../shared/feedback/app_snack.dart';
import '../shared/feedback/haptics.dart';
import '../shared/widgets/run_limit_chips.dart';
import 'sensors_sheet.dart';
import '../stats/device_stats_cubit.dart';
import '../theme/app_colors.dart';

/// The Settings tab (option A / H1 layout).
///
/// A `paper`-ground list of white cards, each under an uppercase section
/// label. The per-geyser section carries the device switcher *in its
/// label* ("This geyser · `<name>` ▾") — the single source of truth is the
/// [DeviceRegistryCubit], so picking a device here fans out to the stats
/// and control cubits and the dashboard PageView via the
/// DeviceSelectionCoordinator, exactly as a dashboard swipe does.
///
/// Global sections (Alerts, Account, About) are unscoped.
class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
          child: Text(
            'Settings',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: -0.3,
            ),
          ),
        ),

        // ── Alerts (global) — surfaced first ──────────────────────────
        const _SectionLabel('Alerts'),
        _SettingsCard(
          child: Column(
            children: [
              const _SystemNotificationRow(),
              const _RowDivider(),
              _NotificationSettingsRow(onChanged: () => setState(() {})),
            ],
          ),
        ),
        const SizedBox(height: 22),

        // ── This geyser (scoped) ──────────────────────────────────────
        const _ThisGeyserSection(),
        const SizedBox(height: 22),

        // ── Devices (global) ──────────────────────────────────────────
        const _SectionLabel('Devices'),
        _SettingsCard(
          child: BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
            builder: (context, regState) {
              final count = regState.devices.length;
              return _SettingsRow(
                icon: Icons.devices_other_outlined,
                title: 'Manage devices',
                subtitle: count <= 1
                    ? '1 device registered'
                    : '$count devices registered',
                trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                onTap: () =>
                    Navigator.of(context).push(DeviceManagementPage.route()),
              );
            },
          ),
        ),
        const SizedBox(height: 22),

        // ── Account (global) ──────────────────────────────────────────
        const _SectionLabel('Account'),
        const _AccountSection(),
        const SizedBox(height: 22),

        // ── About (global) ────────────────────────────────────────────
        const _SectionLabel('About'),
        const _AboutSection(),
      ],
    );
  }
}

// ── Section scaffolding ────────────────────────────────────────────────

/// The 11pt uppercase, wide-tracked label above each card (design
/// language §6).
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6, bottom: 10),
      child: Row(
        children: [
          Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.muted,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 2),
            Flexible(child: trailing!),
          ],
        ],
      ),
    );
  }
}

/// A white grouping card on the paper ground (the "Direction B" soft
/// lift — surface stays white, only the depth cue changes).
///
/// The neu dual-shadow sits on the outer container; the inner [Material]
/// carries the white fill, rounds/clips the corners, and — crucially —
/// is the surface the rows' ink ripples paint onto. Without it those
/// ripples would render on the Scaffold material *behind* an opaque card
/// and never show.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: AppColors.neuShadow,
            offset: Offset(4, 4),
            blurRadius: 14,
          ),
          BoxShadow(
            color: AppColors.neuHighlight,
            offset: Offset(-4, -4),
            blurRadius: 14,
          ),
        ],
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}

/// A tappable settings row: leading icon, title, optional subtitle,
/// trailing widget. Kept visually flat — the card carries the depth,
/// the rows are "read/tap", not raised (design language §2).
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: iconColor ?? AppColors.inkSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: titleColor ?? AppColors.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A hairline divider inset to clear the leading-icon gutter, so grouped
/// rows read as one card rather than separate strips.
class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 16,
      endIndent: 16,
      color: AppColors.hairline,
    );
  }
}

// ── This geyser (scoped section + H1 switcher) ─────────────────────────

class _ThisGeyserSection extends StatelessWidget {
  const _ThisGeyserSection();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
      builder: (context, regState) {
        final selected = regState.selectedDevice;

        // The switcher lives IN the section label (H1). Single-device:
        // no name, no picker affordance — just "This geyser".
        final Widget? switcher = regState.isMultiDevice && selected != null
            ? _DeviceSwitcher(
                name: selected.nickname,
                onTap: () => _showDevicePicker(context, regState),
              )
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('This geyser', trailing: switcher),
            _SettingsCard(
              child: Column(
                children: [
                  _GeyserSetupRow(),
                  const _RowDivider(),
                  const _SensorsRow(),
                  const _RowDivider(),
                  const _MaxRunControl(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDevicePicker(
    BuildContext context,
    DeviceRegistryState regState,
  ) async {
    final registry = context.read<DeviceRegistryCubit>();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  'Switch geyser',
                  style: Theme.of(sheetCtx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                ),
              ),
              for (var i = 0; i < regState.devices.length; i++)
                ListTile(
                  leading: Icon(
                    i == regState.selectedIndex
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: i == regState.selectedIndex
                        ? AppColors.primary
                        : AppColors.muted,
                  ),
                  title: Text(regState.devices[i].nickname),
                  onTap: () {
                    if (i != regState.selectedIndex) Haptics.select();
                    registry.selectDevice(i);
                    Navigator.pop(sheetCtx);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// The tappable "· `<name>` ▾" affordance appended to the section label.
class _DeviceSwitcher extends StatelessWidget {
  const _DeviceSwitcher({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '· ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.muted,
              ),
            ),
            Flexible(
              child: Text(
                name.toUpperCase(),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: AppColors.primary,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

/// The geyser-setup summary row + editor dialog. Scoped to the selected
/// device — settings are stored per-device.
/// The Sensors declaration row — per-device; opens [showSensorsSheet].
class _SensorsRow extends StatefulWidget {
  const _SensorsRow();

  @override
  State<_SensorsRow> createState() => _SensorsRowState();
}

class _SensorsRowState extends State<_SensorsRow> {
  @override
  Widget build(BuildContext context) {
    final deviceId =
        context.watch<DeviceRegistryCubit>().state.selectedRtdbId;
    if (deviceId == null) return const SizedBox.shrink();

    final prefs = getIt<PrefsManager>();
    final installed = [
      'Temperature',
      if (prefs.hasLeakSensor(deviceId)) 'Leak',
      if (prefs.hasCurrentSensor(deviceId)) 'Current',
    ].join(' · ');

    return _SettingsRow(
      icon: Icons.sensors_rounded,
      title: 'Sensors',
      subtitle: installed,
      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
      onTap: () async {
        await showSensorsSheet(context, deviceId: deviceId);
        // Re-render the subtitle with any changes made in the sheet.
        if (mounted) setState(() {});
      },
    );
  }
}

class _GeyserSetupRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DeviceStatsCubit, DeviceStatsState>(
      builder: (context, state) {
        final c = state.config;
        return _SettingsRow(
          icon: Icons.tune_rounded,
          title: 'Geyser setup',
          subtitle: '${c.tankSize}L · ${c.elementKw.toStringAsFixed(1)} kW · '
              'R${c.costPerKwh.toStringAsFixed(2)}/kWh',
          trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
          onTap: () => _showGeyserSetupDialog(context),
        );
      },
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

    await showDialog<void>(
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
                    'All settings are saved per-device so '
                    'each geyser can have its own configuration.',
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
                      helperText: 'Eskom: ~R2.71 · City Power: ~R3.16\n'
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
                  Haptics.commit();
                  final parsed = double.tryParse(rateController.text);
                  if (parsed != null && parsed > 0) {
                    config = config.copyWith(costPerKwh: parsed);
                  }
                  // Captured before the awaits/pop invalidate ctx.
                  final messenger = ScaffoldMessenger.of(ctx);
                  if (deviceId != null) {
                    await configRepo.saveConfig(deviceId, config);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  Haptics.success();
                  messenger.showSnackBar(appSnackBar(
                    type: AppSnackType.success,
                    message: 'Geyser setup saved',
                  ));
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
}

// ── Max continuous run (moved from the device-management page) ─────────

/// Collapsed to its title + description by default; the duration chips
/// reveal on tap and the card folds shut again the instant one is picked,
/// so the resting Settings list stays quiet.
class _MaxRunControl extends StatefulWidget {
  const _MaxRunControl();

  @override
  State<_MaxRunControl> createState() => _MaxRunControlState();
}

class _MaxRunControlState extends State<_MaxRunControl> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<GeyserControlCubit, GeyserControlState>(
      buildWhen: (prev, curr) =>
          prev.snapshot.maxOnMinutes != curr.snapshot.maxOnMinutes,
      builder: (context, state) {
        final current = state.snapshot.maxOnMinutes;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The whole title line is the tap target that folds the chips
            // in and out.
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.timer_off_outlined,
                            size: 22, color: AppColors.inkSecondary),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            'Max continuous run',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        Text(
                          _labelFor(current),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: current == 0
                                ? AppColors.warning
                                : AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        AnimatedRotation(
                          turns: _expanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: const Icon(Icons.expand_more,
                              size: 22, color: AppColors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      current == 0
                          ? 'Off — the geyser stays powered until a timer, your '
                              'temperature limit, or you switch it off.'
                          : 'Caps a single heating stretch. An energy guard, not a '
                              'temperature control — your geyser\'s built-in '
                              'thermostat regulates the water either way.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // The chips only take up room while expanded.
            AnimatedSize(
              alignment: Alignment.topCenter,
              curve: Curves.easeInOut,
              duration: Duration(
                milliseconds:
                    MediaQuery.of(context).disableAnimations ? 0 : 180,
              ),
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RunLimitChips(
                            currentMinutes: current,
                            onSelect: (minutes) {
                              context
                                  .read<GeyserControlCubit>()
                                  .setMaxOnTimer(minutes);
                              // Fold shut the moment a choice is made.
                              setState(() => _expanded = false);
                            },
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '2 hours suits most geysers — about one full '
                            'heat-up.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: AppColors.muted,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        );
      },
    );
  }

  String _labelFor(int minutes) {
    if (minutes == 0) return 'Off';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h hour${h > 1 ? 's' : ''}';
    return '${h}h ${m}m';
  }
}

// ── Alerts: notification settings row + dialog ─────────────────────────

class _NotificationSettingsRow extends StatelessWidget {
  const _NotificationSettingsRow({required this.onChanged});

  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final anyEnabled = getIt<PrefsManager>().anyNotificationEnabled;
    return _SettingsRow(
      icon: anyEnabled
          ? Icons.notifications_outlined
          : Icons.notifications_off_outlined,
      iconColor: anyEnabled ? AppColors.inkSecondary : AppColors.muted,
      title: 'Notification settings',
      subtitle:
          anyEnabled ? 'Some notifications enabled' : 'All notifications muted',
      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
      onTap: () async {
        await _showNotificationSettingsDialog(context);
        onChanged();
      },
    );
  }

  Future<void> _showNotificationSettingsDialog(BuildContext context) async {
    final prefs = getIt<PrefsManager>();
    final toggles = {
      for (final type in NotificationType.settable)
        type: prefs.isNotificationTypeEnabled(type),
    };

    await showDialog<void>(
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
                Haptics.commit();
                // Captured before the awaits/pop invalidate ctx.
                final messenger = ScaffoldMessenger.of(ctx);
                for (final entry in toggles.entries) {
                  await prefs.setNotificationTypeEnabled(
                    entry.key,
                    entry.value,
                  );
                }
                getIt<NotificationService>().refreshUnreadCount();
                if (ctx.mounted) Navigator.pop(ctx);
                Haptics.success();
                messenger.showSnackBar(appSnackBar(
                  type: AppSnackType.success,
                  message: 'Alert preferences saved',
                ));
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
        return 'When the geyser switches off after its max run time';
      case NotificationType.clockLost:
        return 'When the device loses its clock and pauses the schedule';
      case NotificationType.scheduleRestored:
        return 'When the clock is set again and the schedule resumes';
      case NotificationType.leak:
        return 'When water is detected near the geyser';
      case NotificationType.leakClear:
        return 'When a detected water leak clears';
      case NotificationType.unknown:
        return 'Unknown event type';
    }
  }
}

// ── System notification permission row ──────────────────────────────────
//
// Distinct from the per-type mute settings: this is the OS permission,
// which the app cannot change directly. Without a row like this a user
// who declined has no way back — on iOS the system dialog never appears
// again, so device settings are the only route.

class _SystemNotificationRow extends StatefulWidget {
  const _SystemNotificationRow();

  @override
  State<_SystemNotificationRow> createState() => _SystemNotificationRowState();
}

class _SystemNotificationRowState extends State<_SystemNotificationRow>
    with WidgetsBindingObserver {
  AuthorizationStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Picks up a change made in device settings without a relaunch.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status =
        await getIt<PushNotificationManager>().refreshAuthorizationStatus();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) {
      // Keep the row height stable while the async check resolves.
      return const SizedBox(height: 64);
    }

    final allowed = status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;

    // Nothing to act on when they are already on — the per-type settings
    // below cover the rest.
    if (allowed) {
      return _SettingsRow(
        icon: Icons.check_circle_outline,
        iconColor: AppColors.save,
        title: 'Alerts allowed',
        subtitle: 'Your device lets GeyserSwitch notify you',
      );
    }

    return _SettingsRow(
      icon: Icons.notifications_off_outlined,
      iconColor: Colors.orange.shade700,
      title: 'Alerts are switched off',
      subtitle: status == AuthorizationStatus.denied
          ? 'Turn them on in device settings to hear about your geyser'
          : 'Turn them on to hear about your geyser',
      trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
      onTap: () async {
        await NotificationPrimingSheet.maybeShow(context);
        await _refresh();
      },
    );
  }
}

// ── Account ─────────────────────────────────────────────────────────────

class _AccountSection extends StatelessWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context) {
    final email = getIt<AuthRepository>().currentUser()?.email;

    return _SettingsCard(
      child: Column(
        children: [
          _SettingsRow(
            icon: Icons.account_circle_outlined,
            title: 'Signed in',
            subtitle: email == null || email.isEmpty ? 'Account' : email,
          ),
          const _RowDivider(),
          _SettingsRow(
            icon: Icons.logout_rounded,
            iconColor: AppColors.critical,
            titleColor: AppColors.critical,
            title: 'Sign out',
            onTap: () => confirmSignOut(context),
          ),
        ],
      ),
    );
  }
}

// ── About ───────────────────────────────────────────────────────────────

class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _appVersion = info.version);
    } catch (_) {
      // Leave blank if unavailable — the row simply shows no value.
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        children: [
          _InfoRow(label: 'App version', value: _appVersion),
          const _RowDivider(),
          // Firmware version is read over BLE; null until connected.
          BlocBuilder<GeyserControlCubit, GeyserControlState>(
            buildWhen: (prev, curr) =>
                prev.snapshot.firmwareVersion != curr.snapshot.firmwareVersion,
            builder: (context, state) {
              // The firmware version is only read over BLE (GATT); it is
              // unknown on WiFi/remote, so say what's needed to read it
              // rather than the misleading "not connected".
              final fw = state.snapshot.firmwareVersion;
              final unknown = fw == null || fw.isEmpty;
              return _InfoRow(
                label: 'Firmware',
                value: unknown ? 'Bluetooth required' : fw,
                muted: unknown,
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A read-only label/value row for the About card (no tap affordance).
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.ink,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: muted ? AppColors.muted : AppColors.inkSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sign-out flow (relocated from the dashboard app bar) ────────────────

/// Confirm, then tear down every stream/subscription that holds an
/// authenticated context before Firebase signs out, and scrub the local
/// account data so nothing bleeds into the next signer.
///
/// Lives here now that Sign out is a Settings › Account action; the
/// app-bar logout icon is gone.
Future<void> confirmSignOut(BuildContext context) async {
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

  // Grab context-dependent cubits before any awaits — the page can be
  // disposed mid-teardown once auth state starts changing, and reading a
  // deactivated context throws.
  final bleCubit = context.read<BleConnectionCubit>();
  final registryCubit = context.read<DeviceRegistryCubit>();

  // Tear down singletons that hold streams/subscriptions before Firebase
  // Auth signs out. This prevents them from operating on a signed-out
  // auth context.
  await getIt<TelemetryRecorder>().stop();
  await getIt<NotificationService>().stop();
  await getIt<GeyserControlCubit>().resetForSignOut();
  bleCubit.unpair();
  registryCubit.clear();
  await getIt<PrefsManager>().clearDeviceData();

  // Account data hygiene. The Drift rows carry no uid — anything left
  // behind would be uploaded into the NEXT signer's cloud account. And
  // without deleting the FCM token, this phone keeps receiving the
  // signed-out account's geyser alerts indefinitely.
  await getIt<TelemetryRepository>().deleteAll();
  await getIt<NotificationRepository>().deleteAll();
  await getIt<PushNotificationManager>().unregisterToken();

  await getIt<SignOut>().call();
}
