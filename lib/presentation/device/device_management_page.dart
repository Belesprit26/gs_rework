import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/ble/ble_owner_auth.dart';
import '../../data/local/prefs_manager.dart';
import '../../di/locator.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../ble/ble_connection_cubit.dart';
import '../ble/device_scan_page.dart';
import '../shared/feedback/app_snack.dart';
import '../shared/feedback/haptics.dart';
import '../shared/widgets/neu/neu.dart';
import '../theme/app_colors.dart';
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
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Manage Devices'),
        backgroundColor: AppColors.paper,
      ),
      // Neu primary CTA pinned to the bottom (replaces the Material FAB).
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(DeviceScanPage.route()),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  offset: const Offset(3, 3),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, size: 19, color: Colors.white),
                SizedBox(width: 8),
                Text(
                  'Add Device',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: BlocBuilder<DeviceRegistryCubit, DeviceRegistryState>(
        builder: (context, regState) {
          if (regState.devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const NeuRaisedCircle(
                    size: 88,
                    child: Icon(Icons.devices_other,
                        size: 36, color: AppColors.muted),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'No devices registered',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Pair your first GeyserSwitch below',
                    style: TextStyle(
                        fontSize: 14, color: AppColors.inkSecondary),
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

    // SoftCard-style row; the SELECTED device carries a soft teal glow
    // instead of a hard border (the NeuPanel glowColor grammar).
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          ...neuRaisedShadows(distance: 4, blur: 10),
          if (isSelected)
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 14,
              spreadRadius: 1,
            ),
        ],
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
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
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.neuBase,
        boxShadow: [
          ...neuRaisedShadows(distance: 2, blur: 5),
          if (isConnected)
            BoxShadow(
              color: AppColors.rampBlue.withValues(alpha: 0.28),
              blurRadius: 6,
              spreadRadius: 0.5,
            ),
        ],
      ),
      child: Icon(
        isConnected
            ? Icons.bluetooth_connected
            : Icons.bluetooth_disabled_outlined,
        size: 18,
        color: isConnected
            ? AppColors.ink.withValues(alpha: 0.72)
            : AppColors.muted,
      ),
    );
  }

  String get _statusLabel {
    if (isBusy) return 'Connecting…';
    if (isConnected) return 'Connected';
    if (isSelected) return 'Selected · Offline';
    return 'Offline';
  }

  Color get _statusColor {
    if (isConnected) return AppColors.rampBlue;
    if (isBusy) return AppColors.warning;
    return AppColors.muted;
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
    Haptics.commit();
    // Capture before the pop unmounts the dialog's context.
    final messenger = ScaffoldMessenger.of(ctx);
    prefs.setDeviceNickname(device.rtdbDeviceId, name);
    registry.updateNickname(device.rtdbDeviceId, name);
    Navigator.pop(ctx);
    Haptics.success();
    messenger.showSnackBar(appSnackBar(
      type: AppSnackType.success,
      message: 'Device renamed',
    ));
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
              Haptics.commit();
              Navigator.pop(ctx);
              final ok = await ownerAuth.rotateKey(device.rtdbDeviceId);
              if (ok) {
                Haptics.success();
              } else {
                Haptics.blocked();
              }
              // Messenger was captured before the async gap; success and
              // failure now carry distinct severities.
              messenger.showSnackBar(appSnackBar(
                type: ok ? AppSnackType.success : AppSnackType.error,
                message: ok
                    ? 'Access key reset.'
                    : "Couldn't reset the key — connect to the device "
                        'and try again.',
              ));
            },
            child: const Text('Reset key'),
          ),
        ],
      ),
    );
  }
}

enum _Action { rename, remove, resetKey }
