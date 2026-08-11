import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../domain/ble/ble_connection_status.dart';
import '../../domain/ble/entities/scanned_device.dart';
import '../notifications/notification_priming_sheet.dart';
import '../provisioning/provisioning_sheet.dart';
import '../shared/feedback/haptics.dart';
import '../shared/widgets/neu/neu.dart';
import '../theme/app_colors.dart';
import 'ble_connection_cubit.dart';

/// Full-screen page that scans for GeyserSwitch devices and lets
/// the user select one to pair with.
///
/// Neu-styled (UX polish E1); all connection logic lives in
/// [BleConnectionCubit] and is unchanged by the restyle.
class DeviceScanPage extends StatelessWidget {
  const DeviceScanPage({super.key});

  static Route<void> route() =>
      MaterialPageRoute(builder: (_) => const DeviceScanPage());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('Pair Device'),
        backgroundColor: AppColors.paper,
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
          // The connection the user was watching just landed.
          Haptics.success();
          // Show the provisioning modal on first connection.
          final provisioned = await showProvisioningSheet(context);
          if (!context.mounted) return;

          // Refresh device info after provisioning.
          context.read<BleConnectionCubit>().refreshDeviceInfo();

          // Ask about notifications here, with a geyser freshly set up,
          // rather than cold at app launch — see the sheet's docs.
          if (provisioned == true) {
            await NotificationPrimingSheet.maybeShow(context);
            if (!context.mounted) return;
          }
          Navigator.of(context).pop();
        },
        builder: (context, state) {
          // ── Connected state: show paired device, not scan controls ─
          if (state.isConnected) {
            return _ConnectedView(state: state);
          }

          // ── Bluetooth off: prompt to enable ──────────────────────
          if (!state.isBluetoothOn) {
            return _BluetoothOffView(state: state);
          }

          // ── Disconnected state: scan controls ──────────────────────
          return Column(
            children: [
              _StatusCard(state: state),

              // ── Scan button ────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: _ScanButton(
                  isScanning: state.isScanning,
                  isBusy: state.isBusy,
                  onPressed: state.isScanning
                      ? () => context.read<BleConnectionCubit>().stopScan()
                      : state.isBusy
                          ? null
                          : () =>
                              context.read<BleConnectionCubit>().startScan(),
                ),
              ),

              // ── Error message ──────────────────────────────────────
              if (state.scanError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    state.scanError!,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.critical),
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
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        itemCount: state.scannedDevices.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final device = state.scannedDevices[index];
                          return _DeviceTile(
                            device: device,
                            isBusy: state.isBusy,
                            onTap: () {
                              Haptics.tap();
                              context
                                  .read<BleConnectionCubit>()
                                  .connectToDevice(device);
                            },
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

// ── Connected view ────────────────────────────────────────────────────

class _ConnectedView extends StatelessWidget {
  const _ConnectedView({required this.state});

  final BleConnectionState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusCard(state: state),
        const SizedBox(height: 36),

        // Device disc — the connection made physical.
        NeuRaisedCircle(
          size: 96,
          child: Icon(
            Icons.bluetooth_connected,
            size: 40,
            color: AppColors.ink.withValues(alpha: 0.72),
          ),
        ),
        if (state.isWifiProvisioned) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_rounded,
                  size: 16, color: AppColors.save),
              const SizedBox(width: 6),
              Text(
                'WiFi configured',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.save.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ],
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
          style: const TextStyle(fontSize: 12, color: AppColors.muted),
        ),
        const SizedBox(height: 28),
        NeuButton(
          label: 'Configure Device',
          primary: true,
          onPressed: () async {
            final provisioned = await showProvisioningSheet(context);
            if (!context.mounted) return;
            // Refresh device info after provisioning.
            context.read<BleConnectionCubit>().refreshDeviceInfo();
            if (provisioned == true) {
              await NotificationPrimingSheet.maybeShow(context);
            }
          },
        ),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () async {
            await context.read<BleConnectionCubit>().unpair();
          },
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.link_off, size: 16, color: AppColors.critical),
                SizedBox(width: 6),
                Text(
                  'Unpair Device',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.critical,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Bluetooth-off view ────────────────────────────────────────────────

class _BluetoothOffView extends StatelessWidget {
  const _BluetoothOffView({required this.state});

  final BleConnectionState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StatusCard(state: state),
        const Spacer(),
        NeuRaisedCircle(
          size: 88,
          child: Icon(Icons.bluetooth_disabled,
              size: 36, color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        const Text(
          'Bluetooth is Off',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Turn on Bluetooth to scan for\nGeyserSwitch devices',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.inkSecondary),
        ),
        const SizedBox(height: 24),
        NeuButton(
          label: 'Turn On Bluetooth',
          primary: true,
          onPressed: () async {
            try {
              await FlutterBluePlus.turnOn();
            } catch (_) {
              // iOS doesn't support turnOn — user must do it manually.
            }
          },
        ),
        const Spacer(),
      ],
    );
  }
}

// ── Status card ───────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final BleConnectionState state;

  @override
  Widget build(BuildContext context) {
    final (Color halo, IconData icon) = switch (state.connectionStatus) {
      BleConnectionStatus.ready => (
          AppColors.rampBlue,
          Icons.bluetooth_connected
        ),
      BleConnectionStatus.connecting ||
      BleConnectionStatus.discoveringServices ||
      BleConnectionStatus.reconnecting => (
          AppColors.warning,
          Icons.bluetooth_searching
        ),
      BleConnectionStatus.scanning => (
          AppColors.rampBlue,
          Icons.bluetooth_searching
        ),
      BleConnectionStatus.disconnected => (
          AppColors.muted,
          Icons.bluetooth_disabled
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: neuRaisedShadows(distance: 4, blur: 12),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.neuBase,
                boxShadow: [
                  ...neuRaisedShadows(distance: 2, blur: 5),
                  BoxShadow(
                    color: halo.withValues(alpha: 0.28),
                    blurRadius: 6,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: Icon(icon,
                  size: 18, color: AppColors.ink.withValues(alpha: 0.72)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                state.statusLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (state.isWifiProvisioned && state.isConnected) ...[
              const Icon(Icons.wifi_rounded,
                  size: 16, color: AppColors.save),
              const SizedBox(width: 8),
            ],
            if (state.isPaired)
              Text(
                state.displayName,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.inkSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Scan button ───────────────────────────────────────────────────────

class _ScanButton extends StatelessWidget {
  const _ScanButton({
    required this.isScanning,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isScanning;
  final bool isBusy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return GestureDetector(
      onTap: onPressed,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: double.infinity,
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isScanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              else
                const Icon(Icons.bluetooth_searching,
                    size: 18, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                isScanning ? 'Stop Scan' : 'Scan',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Device tile ───────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.isBusy,
    required this.onTap,
  });

  final ScannedDevice device;
  final bool isBusy;
  final VoidCallback onTap;

  /// 0–4 bars from RSSI, matching the old text buckets.
  int get _bars {
    if (device.rssi >= -50) return 4; // Excellent
    if (device.rssi >= -65) return 3; // Good
    if (device.rssi >= -80) return 2; // Fair
    return 1; // Weak
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: Opacity(
        opacity: isBusy ? 0.6 : 1,
        child: SoftCard(
          padding: const EdgeInsets.all(14),
          borderRadius: 16,
          distance: 4,
          blur: 10,
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.neuBase,
                  boxShadow: neuRaisedShadows(distance: 2, blur: 5),
                ),
                child: const Icon(Icons.bluetooth,
                    size: 19, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name.isEmpty ? 'Unknown device' : device.name,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      device.id,
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              _SignalDots(bars: _bars),
              const SizedBox(width: 8),
              if (isBusy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four ascending signal bars; lit count = strength.
class _SignalDots extends StatelessWidget {
  const _SignalDots({required this.bars});

  final int bars;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < 4; i++) ...[
          if (i > 0) const SizedBox(width: 2.5),
          Container(
            width: 4,
            height: 6.0 + i * 3.5,
            decoration: BoxDecoration(
              color: i < bars
                  ? AppColors.primary
                  : AppColors.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}
