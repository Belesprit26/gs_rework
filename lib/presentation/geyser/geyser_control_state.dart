part of 'geyser_control_cubit.dart';

/// Which communication channel is active.
enum GeyserMode { ble, remote, offline }

class GeyserControlState extends Equatable {
  const GeyserControlState({
    this.snapshot = const GeyserSnapshot(),
    this.bleStatus = BleConnectionStatus.disconnected,
    this.mode = GeyserMode.offline,
    this.isLoading = false,
    this.isBusy = false,
    this.error,
    this.deviceLastSeen,
    this.deviceOffline = false,
  });

  /// The latest geyser data (from BLE or RTDB).
  final GeyserSnapshot snapshot;

  /// Current BLE connection status.
  final BleConnectionStatus bleStatus;

  /// Active communication channel.
  final GeyserMode mode;

  /// True while the initial snapshot is being fetched.
  final bool isLoading;

  /// True while a write command (toggle, set limits) is in flight.
  final bool isBusy;

  /// Last error message, or null.
  final String? error;

  /// Last time the ESP pushed telemetry (from RTDB `live/{did}/at`).
  /// Only populated in remote mode.
  final DateTime? deviceLastSeen;

  /// True when in remote mode and the ESP hasn't pushed data recently.
  /// Updated by a periodic heartbeat timer in the cubit.
  final bool deviceOffline;

  // ── Derived helpers ───────────────────────────────────────────────

  bool get isConnected =>
      bleStatus == BleConnectionStatus.ready ||
      mode == GeyserMode.remote;
  bool get hasData => isConnected && !isLoading;

  // ── Copy helper ───────────────────────────────────────────────────

  GeyserControlState copyWith({
    GeyserSnapshot? snapshot,
    BleConnectionStatus? bleStatus,
    GeyserMode? mode,
    bool? isLoading,
    bool? isBusy,
    bool? deviceOffline,
    Object? error = _sentinel,
    Object? deviceLastSeen = _sentinel,
  }) {
    return GeyserControlState(
      snapshot: snapshot ?? this.snapshot,
      bleStatus: bleStatus ?? this.bleStatus,
      mode: mode ?? this.mode,
      isLoading: isLoading ?? this.isLoading,
      isBusy: isBusy ?? this.isBusy,
      deviceOffline: deviceOffline ?? this.deviceOffline,
      error: identical(error, _sentinel) ? this.error : error as String?,
      deviceLastSeen: identical(deviceLastSeen, _sentinel)
          ? this.deviceLastSeen
          : deviceLastSeen as DateTime?,
    );
  }

  @override
  List<Object?> get props => [
        snapshot,
        bleStatus,
        mode,
        isLoading,
        isBusy,
        deviceOffline,
        error,
        deviceLastSeen,
      ];
}
