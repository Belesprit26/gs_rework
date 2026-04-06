import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/local/prefs_manager.dart';
import '../../di/locator.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../ble/ble_connection_cubit.dart';
import '../ble/device_scan_page.dart';
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
              return ListView.separated(
                padding: const EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 88,
                ),
                itemCount: regState.devices.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final device = regState.devices[index];
                  final isSelected = index == regState.selectedIndex;
                  final isConnected =
                      bleState.connectionStatus == BleConnectionStatus.ready &&
                          bleState.pairedDeviceId == device.bleMac;
                  final isBusy =
                      bleState.pairedDeviceId == device.bleMac &&
                          bleState.isBusy;

                  return _DeviceCard(
                    device: device,
                    isSelected: isSelected,
                    isConnected: isConnected,
                    isBusy: isBusy,
                  );
                },
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
}

enum _Action { rename, remove }
