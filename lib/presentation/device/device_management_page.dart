import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/ble/ble_owner_auth.dart';
import '../../data/local/prefs_manager.dart';
import '../../di/locator.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../ble/ble_connection_cubit.dart';
import '../ble/device_scan_page.dart';
import '../geyser/geyser_control_cubit.dart';
import 'device_registry_cubit.dart';

/// Lists all registered GeyserSwitch devices with rename/remove
/// and an entry point into the existing [DeviceScanPage] pairing flow.
class DeviceManagementPage extends StatelessWidget {
  const DeviceManagementPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const DeviceManagementPage());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Devices')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(DeviceScanPage.route()),
        icon: const Icon(Icons.add),
        label: const Text('Add Device'),
      ),
      body: BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
        builder: (context, regState) {
          if (regState.devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.devices_other,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No devices registered',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to pair your first GeyserSwitch',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade500,
                        ),
                  ),
                ],
              ),
            );
          }

          return BlocBuilder<BleConnectionCubit, BleConnectionState>(
            builder: (context, bleState) {
              return ListView(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 88,
                ),
                children: [
                  ...List.generate(regState.devices.length, (index) {
                    final device = regState.devices[index];
                    final isSelected = index == regState.selectedIndex;
                    final isConnected =
                        bleState.connectionStatus ==
                                BleConnectionStatus.ready &&
                            bleState.pairedDeviceId == device.bleMac;
                    final isBusy =
                        bleState.pairedDeviceId == device.bleMac &&
                            bleState.isBusy;

                    return Padding(
                      padding: EdgeInsets.only(
                          bottom: index < regState.devices.length - 1 ? 8 : 0),
                      child: _DeviceCard(
                        device: device,
                        isSelected: isSelected,
                        isConnected: isConnected,
                        isBusy: isBusy,
                      ),
                    );
                  }),

                  const SizedBox(height: 24),
                  const _MaxOnTimerSection(),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.isSelected,
    required this.isConnected,
    required this.isBusy,
  });

  final DeviceInfo device;
  final bool isSelected;
  final bool isConnected;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: isSelected ? 2 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide(color: Colors.grey.shade300),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: _buildStatusIcon(cs),
        title: Text(
          device.nickname,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _statusLabel,
          style: theme.textTheme.bodySmall?.copyWith(color: _statusColor),
        ),
        trailing: PopupMenuButton<_Action>(
          onSelected: (action) => _onAction(context, action),
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: _Action.rename,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Rename'),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (isConnected)
              const PopupMenuItem(
                value: _Action.resetKey,
                child: ListTile(
                  leading: Icon(Icons.key_outlined),
                  title: Text('Reset access key'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            PopupMenuItem(
              value: _Action.remove,
              child: ListTile(
                leading: Icon(Icons.delete_outline,
                    color: theme.colorScheme.error),
                title: Text('Remove',
                    style: TextStyle(color: theme.colorScheme.error)),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ColorScheme cs) {
    if (isBusy) {
      return SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          color: cs.primary,
        ),
      );
    }
    return Icon(
      isConnected
          ? Icons.bluetooth_connected
          : Icons.bluetooth_disabled_outlined,
      color: isConnected ? cs.primary : Colors.grey.shade400,
    );
  }

  String get _statusLabel {
    if (isBusy) return 'Connecting…';
    if (isConnected) return 'Connected';
    if (isSelected) return 'Selected · Offline';
    return 'Offline';
  }

  Color get _statusColor {
    if (isConnected) return Colors.blue.shade700;
    if (isBusy) return Colors.orange.shade700;
    return Colors.grey.shade500;
  }

  void _onAction(BuildContext context, _Action action) {
    switch (action) {
      case _Action.rename:
        _showRenameDialog(context);
      case _Action.remove:
        _showRemoveConfirmation(context);
      case _Action.resetKey:
        _showResetKeyConfirmation(context);
    }
  }

  void _showRenameDialog(BuildContext context) {
    final controller = TextEditingController(text: device.nickname);
    final prefs = getIt<PrefsManager>();
    final registry = context.read<DeviceRegistryCubit>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Device'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Device name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _doRename(ctx, controller, prefs, registry),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => _doRename(ctx, controller, prefs, registry),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _doRename(
    BuildContext ctx,
    TextEditingController controller,
    PrefsManager prefs,
    DeviceRegistryCubit registry,
  ) {
    final name = controller.text.trim();
    if (name.isEmpty) return;
    prefs.setDeviceNickname(device.rtdbDeviceId, name);
    registry.updateNickname(device.rtdbDeviceId, name);
    Navigator.pop(ctx);
  }

  void _showRemoveConfirmation(BuildContext context) {
    final registry = context.read<DeviceRegistryCubit>();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Device'),
        content: Text(
          'Remove "${device.nickname}" from your device list?\n\n'
          'This only unregisters it from this phone. '
          'The device itself is not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              registry.removeDevice(device.rtdbDeviceId);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _showResetKeyConfirmation(BuildContext context) {
    final ownerAuth = getIt<BleOwnerAuth>();
    final messenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset access key'),
        content: Text(
          'Generate a new BLE access key for "${device.nickname}".\n\n'
          'Other phones will lose local (Bluetooth) control until they '
          'reconnect while signed into this account. Use this if a phone '
          'that had access should no longer control the geyser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await ownerAuth.rotateKey(device.rtdbDeviceId);
              messenger.showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Access key reset.'
                      : 'Could not reset the key — connect to the device and try again.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text('Reset key'),
          ),
        ],
      ),
    );
  }
}

enum _Action { rename, remove, resetKey }

// ── Max continuous run timer ─────────────────────────────────────────

class _MaxOnTimerSection extends StatelessWidget {
  const _MaxOnTimerSection();

  /// Durations stop two minutes short of the round hour on purpose.
  /// A duration exactly equal to the gap between two scheduled slots
  /// (2 h with timers at 04:00 and 06:00) would end one block at the
  /// very moment the next timer fires; ending early keeps every block
  /// boundary clean. Firmware ≥ 0.7.0 also guards against this, so the
  /// values are belt-and-braces rather than load-bearing.
  static const _presets = [
    (label: 'Off', minutes: 0),
    (label: '58 min', minutes: 58),
    (label: '1 h 58 m', minutes: 118),
    (label: '3 h 58 m', minutes: 238),
    (label: '5 h 58 m', minutes: 358),
    (label: '7 h 58 m', minutes: 478),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<GeyserControlCubit, GeyserControlState>(
      buildWhen: (prev, curr) =>
          prev.snapshot.maxOnMinutes != curr.snapshot.maxOnMinutes,
      builder: (context, state) {
        final current = state.snapshot.maxOnMinutes;
        final label = _labelFor(current);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Energy & Runtime',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                )),
            const SizedBox(height: 8),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.grey.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.timer_off_outlined,
                            size: 20, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Max Continuous Run',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                        Text(label,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: current == 0
                                  ? Colors.orange.shade700
                                  : theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            )),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      current == 0
                          ? 'Off — the geyser stays powered until a timer, '
                              'your temperature limit, or you switch it off.'
                          : 'Caps a single heating stretch at $label. '
                              'Useful if the geyser is left on by accident.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'This is an energy guard, not a temperature control — '
                      'your geyser\'s built-in thermostat regulates the '
                      'water either way.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _presets.map((p) {
                        final selected = p.minutes == current;
                        return ChoiceChip(
                          label: Text(p.label),
                          selected: selected,
                          onSelected: (_) {
                            context
                                .read<GeyserControlCubit>()
                                .setMaxOnTimer(p.minutes);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Recommended: 3 h 58 m. Caps how long the geyser can '
                      'draw power in one stretch. Your geyser\'s built-in '
                      'thermostat is unaffected.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Blocks end two minutes early so the next scheduled '
                      'block starts cleanly.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _labelFor(int minutes) {
    if (minutes == 0) return 'Disabled';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '$h hour${h > 1 ? 's' : ''}';
    return '${h}h ${m}m';
  }
}
