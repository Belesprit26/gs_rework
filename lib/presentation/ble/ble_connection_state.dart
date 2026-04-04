part of 'ble_connection_cubit.dart';

class BleConnectionState extends Equatable {
  const BleConnectionState({
    this.connectionStatus = BleConnectionStatus.disconnected,
    this.scannedDevices = const [],
    this.pairedDeviceId,
    this.pairedDeviceName,
    this.scanError,
    this.isWifiProvisioned = false,
    this.wifiSsid,
    this.deviceNickname,
    this.isBluetoothOn = false,
  });

  final BleConnectionStatus connectionStatus;
  final List<ScannedDevice> scannedDevices;
  final String? pairedDeviceId;
  final String? pairedDeviceName;
  final String? scanError;

  /// Whether the device has WiFi credentials stored and connected.
  final bool isWifiProvisioned;

  /// The stored WiFi SSID (read from device).
  final String? wifiSsid;

  /// The device nickname read from the device (e.g. "Buti").
  final String? deviceNickname;

  /// Whether the phone's Bluetooth adapter is currently on.
  final bool isBluetoothOn;

  // ── Derived helpers ───────────────────────────────────────────────

  bool get isConnected => connectionStatus == BleConnectionStatus.ready;
  bool get isScanning => connectionStatus == BleConnectionStatus.scanning;
  bool get isPaired => pairedDeviceId != null;

  bool get isBusy =>
      connectionStatus == BleConnectionStatus.connecting ||
      connectionStatus == BleConnectionStatus.discoveringServices ||
      connectionStatus == BleConnectionStatus.reconnecting;

  /// The display name for the device, incorporating the nickname.
  String get displayName {
    if (deviceNickname != null && deviceNickname!.isNotEmpty) {
      return 'GeyserSwitch-$deviceNickname';
    }
    return pairedDeviceName ?? 'GeyserSwitch';
  }

  String get statusLabel {
    switch (connectionStatus) {
      case BleConnectionStatus.disconnected:
        if (!isBluetoothOn) return 'Bluetooth Off';
        return isPaired ? 'Disconnected' : 'Not paired';
      case BleConnectionStatus.scanning:
        return 'Scanning…';
      case BleConnectionStatus.connecting:
        return 'Connecting…';
      case BleConnectionStatus.discoveringServices:
        return 'Setting up…';
      case BleConnectionStatus.ready:
        return 'Connected';
      case BleConnectionStatus.reconnecting:
        return 'Reconnecting…';
    }
  }

  // ── Copy helper ───────────────────────────────────────────────────

  BleConnectionState copyWith({
    BleConnectionStatus? connectionStatus,
    List<ScannedDevice>? scannedDevices,
    Object? pairedDeviceId = _sentinel,
    Object? pairedDeviceName = _sentinel,
    Object? scanError = _sentinel,
    bool? isWifiProvisioned,
    Object? wifiSsid = _sentinel,
    Object? deviceNickname = _sentinel,
    bool? isBluetoothOn,
  }) {
    return BleConnectionState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      scannedDevices: scannedDevices ?? this.scannedDevices,
      pairedDeviceId: identical(pairedDeviceId, _sentinel)
          ? this.pairedDeviceId
          : pairedDeviceId as String?,
      pairedDeviceName: identical(pairedDeviceName, _sentinel)
          ? this.pairedDeviceName
          : pairedDeviceName as String?,
      scanError: identical(scanError, _sentinel)
          ? this.scanError
          : scanError as String?,
      isWifiProvisioned: isWifiProvisioned ?? this.isWifiProvisioned,
      wifiSsid: identical(wifiSsid, _sentinel)
          ? this.wifiSsid
          : wifiSsid as String?,
      deviceNickname: identical(deviceNickname, _sentinel)
          ? this.deviceNickname
          : deviceNickname as String?,
      isBluetoothOn: isBluetoothOn ?? this.isBluetoothOn,
    );
  }

  @override
  List<Object?> get props => [
        connectionStatus,
        scannedDevices,
        pairedDeviceId,
        pairedDeviceName,
        scanError,
        isWifiProvisioned,
        wifiSsid,
        deviceNickname,
        isBluetoothOn,
      ];
}
