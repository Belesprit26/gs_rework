import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/ble/ble_connection_status.dart';
import '../../domain/ble/entities/scanned_device.dart';
import '../provisioning/provisioning_sheet.dart';
import 'ble_connection_cubit.dart';

/// Full-screen page that scans for GeyserSwitch devices and lets
/// the user select one to pair with.
class DeviceScanPage extends StatelessWidget {
  const DeviceScanPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const DeviceScanPage());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pair Device'),
      ),
      body: BlocConsumer<BleConnectionCubit, BleConnectionState>(
        listenWhen: (prev, curr) =>
            prev.connectionStatus != curr.connectionStatus &&
            // Only trigger when we've just finished a new connection
            // (went from busy/scanning → ready), not when re-entering
            // the page while already connected.
            !prev.isConnected &&
            curr.isConnected,
        listener: (context, state) async {
          // Show the provisioning modal on first connection.
          await showProvisioningSheet(context);
          if (context.mounted) {
            // Refresh device info after provisioning.
            context.read<BleConnectionCubit>().refreshDeviceInfo();
            Navigator.of(context).pop();
          }
        },
        builder: (context, state) {
          // ── Connected state: show paired device, not scan controls ─
          if (state.isConnected) {
            return Column(
              children: [
                _StatusBanner(state: state),
                const SizedBox(height: 32),

                // ── Connection icons ──────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bluetooth_connected,
                        size: 48, color: Colors.blue),
                    if (state.isWifiProvisioned) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.wifi, size: 48, color: Colors.green),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  state.displayName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  state.pairedDeviceId ?? '',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    await showProvisioningSheet(context);
                    if (context.mounted) {
                      // Refresh device info after provisioning.
                      context.read<BleConnectionCubit>().refreshDeviceInfo();
                    }
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Configure Device'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    await context.read<BleConnectionCubit>().unpair();
                  },
                  icon: const Icon(Icons.link_off),
                  label: const Text('Unpair Device'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .error
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            );
          }

          // ── Bluetooth off: prompt to enable ──────────────────────
          if (!state.isBluetoothOn) {
            return Column(
              children: [
                _StatusBanner(state: state),
                const Spacer(),
                Icon(Icons.bluetooth_disabled,
                    size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  'Bluetooth is Off',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Turn on Bluetooth to scan for\nGeyserSwitch devices',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    try {
                      await FlutterBluePlus.turnOn();
                    } catch (_) {
                      // iOS doesn't support turnOn — user must do it manually.
                    }
                  },
                  icon: const Icon(Icons.bluetooth),
                  label: const Text('Turn On Bluetooth'),
                ),
                const Spacer(),
              ],
            );
          }

          // ── Disconnected state: scan controls ──────────────────────
          return Column(
            children: [
              _StatusBanner(state: state),

              // ── Scan button ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: state.isScanning
                        ? () => context.read<BleConnectionCubit>().stopScan()
                        : state.isBusy
                            ? null
                            : () =>
                                context.read<BleConnectionCubit>().startScan(),
                    icon: state.isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.bluetooth_searching),
                    label: Text(state.isScanning ? 'Stop Scan' : 'Scan'),
                  ),
                ),
              ),

              // ── Error message ──────────────────────────────────────
              if (state.scanError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    state.scanError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),

              // ── Device list ────────────────────────────────────────
              Expanded(
                child: state.scannedDevices.isEmpty
                    ? Center(
                        child: Text(
                          state.isScanning
                              ? 'Looking for GeyserSwitch devices…'
                              : 'Tap Scan to find nearby devices',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: state.scannedDevices.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final device = state.scannedDevices[index];
                          return _DeviceTile(
                            device: device,
                            isBusy: state.isBusy,
                            onTap: () => context
                                .read<BleConnectionCubit>()
                                .connectToDevice(device),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Status Banner ─────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.state});

  final BleConnectionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    Color foregroundColor;
    IconData icon;

    switch (state.connectionStatus) {
      case BleConnectionStatus.ready:
        backgroundColor = Colors.blue.shade50;
        foregroundColor = Colors.blue.shade800;
        icon = Icons.bluetooth_connected;
      case BleConnectionStatus.connecting:
      case BleConnectionStatus.discoveringServices:
      case BleConnectionStatus.reconnecting:
        backgroundColor = Colors.orange.shade50;
        foregroundColor = Colors.orange.shade800;
        icon = Icons.bluetooth_searching;
      case BleConnectionStatus.scanning:
        backgroundColor = Colors.blue.shade50;
        foregroundColor = Colors.blue.shade800;
        icon = Icons.bluetooth_searching;
      case BleConnectionStatus.disconnected:
        backgroundColor = Colors.grey.shade100;
        foregroundColor = Colors.grey.shade700;
        icon = Icons.bluetooth_disabled;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: backgroundColor,
      child: Row(
        children: [
          Icon(icon, color: foregroundColor, size: 20),
          if (state.isWifiProvisioned && state.isConnected) ...[
            const SizedBox(width: 4),
            Icon(Icons.wifi, color: Colors.green.shade700, size: 18),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              state.statusLabel,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (state.isPaired)
            Text(
              state.displayName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: foregroundColor,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Device Tile ───────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isBusy,
    required this.onTap,
  });

  final ScannedDevice device;
  final bool isBusy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Signal strength indicator.
    final strength = _signalStrength(device.rssi);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        Icons.bluetooth,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        device.name.isEmpty ? 'Unknown device' : device.name,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        '${device.id}  •  $strength signal',
        style: theme.textTheme.bodySmall,
      ),
      trailing: isBusy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: isBusy ? null : onTap,
    );
  }

  String _signalStrength(int rssi) {
    if (rssi >= -50) return 'Excellent';
    if (rssi >= -65) return 'Good';
    if (rssi >= -80) return 'Fair';
    return 'Weak';
  }
}
