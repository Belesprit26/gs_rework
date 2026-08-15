import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/local/prefs_manager.dart';
import '../../di/locator.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../ble/ble_connection_cubit.dart';
import '../ble/device_scan_page.dart';
import '../device/device_registry_cubit.dart';
import '../geyser/geyser_control_cubit.dart';
import '../provisioning/provisioning_sheet.dart';
import '../shared/feedback/haptics.dart';
import '../shared/widgets/neu/neu.dart';
import '../theme/app_colors.dart';

// ── Status mapping ────────────────────────────────────────────────────
//
// The connectivity rail badge replaces the old _ModeBanner. This mapper
// reproduces the banner's six states exactly (same predicates, same
// precedence) so nothing an existing user could see is lost — it is
// unit-tested against all six in connectivity_status_test.dart.

/// The badge's view of the connection, derived from
/// [GeyserControlState] + [BleConnectionState].
enum ConnectivityStatus {
  /// BLE connected and ready.
  ble,

  /// Remote (RTDB) mode with a fresh heartbeat.
  wifi,

  /// Remote mode but the device hasn't reported recently.
  deviceOffline,

  /// No path and the phone's Bluetooth is off.
  btOff,

  /// No path at all (BLE dropped, no cloud view).
  notConnected,

  /// A BLE connection attempt is in flight.
  connecting;

  /// The orange "you're not in contact" family.
  bool get isDown =>
      this == deviceOffline || this == btOff || this == notConnected;

  String get title => switch (this) {
        ble => 'Connected via Bluetooth',
        wifi => 'Connected via WiFi',
        deviceOffline => 'Device offline',
        btOff => 'Bluetooth is off',
        notConnected => 'Not connected',
        connecting => 'Connecting…',
      };
}

/// Pure mapper — mirrors the legacy `_ModeBanner` switch, including its
/// precedence (a connecting attempt outranks the Bluetooth-off check).
ConnectivityStatus connectivityStatusFrom(
  GeyserControlState g,
  BleConnectionState b,
) {
  switch (g.mode) {
    case GeyserMode.ble:
      return ConnectivityStatus.ble;
    case GeyserMode.remote:
      return g.deviceOffline
          ? ConnectivityStatus.deviceOffline
          : ConnectivityStatus.wifi;
    case GeyserMode.offline:
      final isBleConnecting =
          g.bleStatus == BleConnectionStatus.connecting ||
              g.bleStatus == BleConnectionStatus.discoveringServices ||
              g.bleStatus == BleConnectionStatus.reconnecting;
      if (isBleConnecting) return ConnectivityStatus.connecting;
      if (!b.isBluetoothOn) return ConnectivityStatus.btOff;
      return ConnectivityStatus.notConnected;
  }
}

/// How one transport is doing, for the hub's per-transport rows.
///
/// The combined [ConnectivityStatus] answers "am I in contact"; this
/// answers "why not, and which half is at fault" — the question a user
/// actually has when a command doesn't land.
enum TransportState {
  /// Carrying commands right now.
  active,

  /// Usable, but not the path in use.
  standby,

  /// Cannot carry a command, for the reason given alongside.
  down,
}

/// A transport's state paired with a reason a person can act on.
class TransportStatus {
  const TransportStatus(this.state, this.detail);

  final TransportState state;

  /// Always concrete — never "unavailable". If it is down, this says what
  /// would fix it; a reason the user cannot act on is not worth showing.
  final String detail;
}

/// Pure mapper — Bluetooth's side of the story.
TransportStatus bluetoothTransportStatus(
  GeyserControlState g,
  BleConnectionState b,
) {
  if (g.mode == GeyserMode.ble) {
    return const TransportStatus(
      TransportState.active,
      'carrying commands now',
    );
  }

  final isConnecting = g.bleStatus == BleConnectionStatus.connecting ||
      g.bleStatus == BleConnectionStatus.discoveringServices ||
      g.bleStatus == BleConnectionStatus.reconnecting;
  if (isConnecting) {
    return const TransportStatus(TransportState.standby, 'connecting…');
  }
  if (!b.isBluetoothOn) {
    return const TransportStatus(
      TransportState.down,
      'turn Bluetooth on in Settings',
    );
  }
  if (!b.isPaired) {
    return const TransportStatus(
      TransportState.down,
      'no device paired yet — use Pair a device',
    );
  }
  // Paired, radio on, still not connected: out of range is the ordinary
  // explanation, and the honest one — we cannot distinguish it from a
  // device that is powered down.
  return const TransportStatus(
    TransportState.down,
    'device not in range, or powered off',
  );
}

/// Pure mapper — WiFi's side of the story.
TransportStatus wifiTransportStatus(
  GeyserControlState g,
  BleConnectionState b,
) {
  if (g.mode == GeyserMode.remote && !g.deviceOffline) {
    return const TransportStatus(
      TransportState.active,
      'carrying commands now',
    );
  }
  if (!b.isWifiProvisioned) {
    return const TransportStatus(
      TransportState.down,
      'device has no WiFi set up — use Configure WiFi',
    );
  }
  if (g.deviceOffline) {
    return const TransportStatus(
      TransportState.down,
      'device has not reported in recently',
    );
  }
  // Provisioned and reporting, just not the active path — which happens
  // whenever Bluetooth wins, since it is preferred when present.
  return const TransportStatus(TransportState.standby, 'ready if needed');
}

/// Compact downtime for the badge caption: "now", "4m", "2h", "3d".
String compactAgo(Duration d) {
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// Sentence downtime for the sheet: "just now", "4 m ago", "2 h ago".
String sentenceAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 30) return 'just now';
  if (diff.inMinutes < 1) return '${diff.inSeconds} s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes} m ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

// ── The badge ─────────────────────────────────────────────────────────

/// The permanent connectivity badge pinned at the top of the focal-card
/// rail. Ink-grey icon with a whisper-thin halo (blue = BLE, green =
/// WiFi); the orange crossed-link states carry a compact "down for X"
/// caption beneath. Tap opens the connection sheet.
///
/// Also the write-through point for the local last-seen record: whenever
/// this widget observes contact (BLE ready / fresh remote heartbeat) it
/// persists the moment, throttled to once a minute.
class ConnectivityBadge extends StatefulWidget {
  const ConnectivityBadge({super.key, required this.deviceId});

  /// Canonical RTDB device id — null before registration (the badge
  /// still renders; only persistence and the caption need the id).
  final String? deviceId;

  @override
  State<ConnectivityBadge> createState() => _ConnectivityBadgeState();
}

class _ConnectivityBadgeState extends State<ConnectivityBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe;
  Timer? _ticker;
  DateTime? _lastPersisted;

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
    _ticker?.cancel();
    _breathe.dispose();
    super.dispose();
  }

  /// Keep the 1-minute caption ticker + breathe animation in step with
  /// the current status. Called from build — both calls are idempotent.
  void _syncAnimations(ConnectivityStatus status, bool reduceMotion) {
    if (status == ConnectivityStatus.connecting && !reduceMotion) {
      if (!_breathe.isAnimating) _breathe.repeat(reverse: true);
    } else {
      if (_breathe.isAnimating) _breathe.stop();
    }

    final wantTicker = status.isDown;
    if (wantTicker && _ticker == null) {
      _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!wantTicker && _ticker != null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Persist "we are in contact now" (throttled) so downtime can be
  /// measured later — including for BLE-only devices and across app
  /// restarts.
  void _maybePersistLastSeen(ConnectivityStatus status, GeyserControlState g) {
    final id = widget.deviceId;
    if (id == null) return;

    DateTime? seen;
    if (status == ConnectivityStatus.ble) {
      seen = DateTime.now();
    } else if (status == ConnectivityStatus.wifi) {
      seen = g.deviceLastSeen ?? DateTime.now();
    }
    if (seen == null) return;
    if (_lastPersisted != null &&
        seen.difference(_lastPersisted!).abs() < const Duration(minutes: 1)) {
      return;
    }
    _lastPersisted = seen;
    getIt<PrefsManager>().setDeviceLastSeenLocal(id, seen);
  }

  /// Best available "last contact": the fresher of the cubit's RTDB
  /// value and the locally persisted record.
  DateTime? _effectiveLastSeen(GeyserControlState g) {
    final local = widget.deviceId == null
        ? null
        : getIt<PrefsManager>().deviceLastSeenLocal(widget.deviceId!);
    final remote = g.deviceLastSeen;
    if (local == null) return remote;
    if (remote == null) return local;
    return remote.isAfter(local) ? remote : local;
  }

  @override
  Widget build(BuildContext context) {
    final gState = context.watch<GeyserControlCubit>().state;
    final bState = context.watch<BleConnectionCubit>().state;
    final status = connectivityStatusFrom(gState, bState);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    _syncAnimations(status, reduceMotion);
    _maybePersistLastSeen(status, gState);

    final lastSeen = status.isDown ? _effectiveLastSeen(gState) : null;

    // Ink-grey icon everywhere except the orange down-states, where the
    // crossed link itself goes orange (user-confirmed spec).
    final (IconData icon, Color iconColor, Color halo) = switch (status) {
      ConnectivityStatus.ble => (
          Icons.bluetooth_connected,
          AppColors.ink.withValues(alpha: 0.72),
          AppColors.rampBlue,
        ),
      ConnectivityStatus.wifi => (
          Icons.wifi_rounded,
          AppColors.ink.withValues(alpha: 0.72),
          AppColors.save,
        ),
      ConnectivityStatus.connecting => (
          Icons.bluetooth_searching,
          AppColors.ink.withValues(alpha: 0.72),
          AppColors.warning,
        ),
      _ => (Icons.link_off_rounded, AppColors.rampOrange, AppColors.rampOrange),
    };

    return Semantics(
      button: true,
      label: '${status.title}. Tap for connection options.',
      child: GestureDetector(
        onTap: () {
          Haptics.tap();
          showConnectivitySheet(context);
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _breathe,
              builder: (context, child) {
                // Steady thin halo (alpha .25); connecting breathes
                // between .15 and .40.
                final alpha = status == ConnectivityStatus.connecting
                    ? 0.15 + 0.25 * _breathe.value
                    : 0.25;
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
                        color: halo.withValues(alpha: alpha),
                        blurRadius: 6,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                  child: child,
                );
              },
              child: Icon(icon, size: 20, color: iconColor),
            ),
            if (lastSeen != null) ...[
              const SizedBox(height: 3),
              Text(
                compactAgo(DateTime.now().difference(lastSeen)),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: AppColors.rampOrange.withValues(alpha: 0.85),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── The connection sheet ──────────────────────────────────────────────

/// One surface, two entrances (rail badge now; app-bar logo in Phase D):
/// live status + last-seen, and state-aware connection/provisioning
/// actions. Watches the cubits so a reconnect updates it in place.
Future<void> showConnectivitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.paper,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) => const _ConnectivitySheetBody(),
  );
}

class _ConnectivitySheetBody extends StatelessWidget {
  const _ConnectivitySheetBody();

  @override
  Widget build(BuildContext context) {
    final gState = context.watch<GeyserControlCubit>().state;
    final bState = context.watch<BleConnectionCubit>().state;
    final regState = context.watch<DeviceRegistryCubit>().state;
    final status = connectivityStatusFrom(gState, bState);

    // One source of truth: the registry says which device this sheet is
    // about, so switching inside the sheet updates everything live.
    final deviceId = regState.selectedRtdbId;
    final deviceName = regState.selectedDevice?.nickname ??
        bState.deviceNickname ??
        'Geyser';

    // Last-seen detail mirrors the badge's caption source.
    DateTime? lastSeen;
    if (status.isDown) {
      final local = deviceId == null
          ? null
          : getIt<PrefsManager>().deviceLastSeenLocal(deviceId);
      final remote = gState.deviceLastSeen;
      lastSeen = switch ((local, remote)) {
        (null, final r) => r,
        (final l, null) => l,
        (final l?, final r?) => r.isAfter(l) ? r : l,
      };
    }

    final subtitle = [
      deviceName,
      if (lastSeen != null) 'last seen ${sentenceAgo(lastSeen)}',
      if (status == ConnectivityStatus.btOff)
        'turn Bluetooth on to reconnect nearby',
    ].join(' · ');

    final (Color statusHalo, Color statusIconColor, IconData statusIcon) =
        switch (status) {
      ConnectivityStatus.ble => (
          AppColors.rampBlue,
          AppColors.ink.withValues(alpha: 0.72),
          Icons.bluetooth_connected,
        ),
      ConnectivityStatus.wifi => (
          AppColors.save,
          AppColors.ink.withValues(alpha: 0.72),
          Icons.wifi_rounded,
        ),
      ConnectivityStatus.connecting => (
          AppColors.warning,
          AppColors.ink.withValues(alpha: 0.72),
          Icons.bluetooth_searching,
        ),
      _ => (
          AppColors.rampOrange,
          AppColors.rampOrange,
          Icons.link_off_rounded,
        ),
    };

    final bleReady = bState.isConnected;
    final canReconnect = !bleReady &&
        bState.isPaired &&
        bState.isBluetoothOn &&
        status != ConnectivityStatus.connecting;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status card ─────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: neuRaisedShadows(distance: 4, blur: 12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.neuBase,
                      boxShadow: [
                        ...neuRaisedShadows(distance: 3, blur: 7),
                        BoxShadow(
                          color: statusHalo.withValues(alpha: 0.28),
                          blurRadius: 6,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                    child:
                        Icon(statusIcon, size: 21, color: statusIconColor),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Device list (2+ devices) ────────────────────────────
            //
            // Selecting here fans out exactly like the Settings picker
            // (registry → coordinator → stats/control/dashboard). Only
            // the SELECTED device has live connection state — a single
            // control cubit follows the selection — so other rows show a
            // neutral radio, not a fabricated status.
            if (regState.isMultiDevice) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(6, 4, 6, 6),
                child: Text(
                  'YOUR GEYSERS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: AppColors.muted,
                  ),
                ),
              ),
              for (var i = 0; i < regState.devices.length; i++)
                GestureDetector(
                  onTap: () {
                    if (i != regState.selectedIndex) Haptics.select();
                    context.read<DeviceRegistryCubit>().selectDevice(i);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 9),
                    child: Row(
                      children: [
                        Icon(
                          i == regState.selectedIndex
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 19,
                          color: i == regState.selectedIndex
                              ? AppColors.primary
                              : AppColors.muted,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            regState.devices[i].nickname,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: i == regState.selectedIndex
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (i == regState.selectedIndex)
                          Icon(statusIcon,
                              size: 16, color: statusIconColor),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 4),
            ],

            // ── Per-transport detail ────────────────────────────────
            // Bluetooth is preferred whenever it is present, so the app
            // can look "stuck on the wrong one" when it is simply using
            // the better path. Showing both, each with its own reason,
            // is what makes that legible.
            const SizedBox(height: 12),
            _TransportRow(
              icon: Icons.bluetooth_rounded,
              label: 'Bluetooth',
              status: bluetoothTransportStatus(gState, bState),
            ),
            const SizedBox(height: 7),
            _TransportRow(
              icon: Icons.wifi_rounded,
              label: 'WiFi',
              status: wifiTransportStatus(gState, bState),
            ),
            const SizedBox(height: 4),

            // ── Actions ─────────────────────────────────────────────
            if (canReconnect)
              _SheetAction(
                icon: Icons.bluetooth_searching,
                label: 'Reconnect via Bluetooth',
                onTap: () {
                  Haptics.tap();
                  // Capture before the pop unmounts this context.
                  final bleCubit = context.read<BleConnectionCubit>();
                  Navigator.of(context).pop();
                  bleCubit.reconnect();
                },
              ),
            _SheetAction(
              icon: Icons.settings_input_antenna,
              label: 'Pair a device',
              onTap: () {
                Haptics.tap();
                // Capture before the pop unmounts this context.
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(DeviceScanPage.route());
              },
            ),
            _SheetAction(
              icon: Icons.wifi_rounded,
              label: 'Configure WiFi',
              enabled: bleReady,
              disabledNote: 'needs Bluetooth',
              onTap: () async {
                Haptics.tap();
                final navigator = Navigator.of(context);
                final bleCubit = context.read<BleConnectionCubit>();
                navigator.pop();
                // The provisioning sheet needs a live context above the
                // (now popped) sheet — the navigator's own is exactly that.
                await showProvisioningSheet(navigator.context);
                bleCubit.refreshDeviceInfo();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// One transport's live state and the reason behind it.
class _TransportRow extends StatelessWidget {
  const _TransportRow({
    required this.icon,
    required this.label,
    required this.status,
  });

  final IconData icon;
  final String label;
  final TransportStatus status;

  @override
  Widget build(BuildContext context) {
    final (Color dot, Color labelColor) = switch (status.state) {
      TransportState.active => (AppColors.save, AppColors.ink),
      TransportState.standby => (
          AppColors.inkSecondary.withValues(alpha: 0.5),
          AppColors.ink,
        ),
      TransportState.down => (
          AppColors.rampOrange,
          AppColors.inkSecondary,
        ),
    };

    return Row(
      children: [
        Icon(icon, size: 16, color: labelColor.withValues(alpha: 0.7)),
        const SizedBox(width: 9),
        SizedBox(
          width: 66,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: labelColor,
            ),
          ),
        ),
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            status.detail,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.inkSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.disabledNote,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final String? disabledNote;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.ink : AppColors.muted;
    final iconColor = enabled ? AppColors.primary : AppColors.muted;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 13),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.hairline)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Text(
              enabled ? '›' : (disabledNote ?? ''),
              style: TextStyle(
                fontSize: enabled ? 16 : 11.5,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
