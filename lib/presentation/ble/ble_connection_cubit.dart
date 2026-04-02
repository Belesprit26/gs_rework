import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/ble/gatt_uuids.dart';
import '../../data/local/prefs_manager.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../../domain/ble/entities/scanned_device.dart';
import '../../domain/ble/repositories/ble_repository.dart';
import '../../domain/provisioning/provisioning_status.dart';

part 'ble_connection_state.dart';

/// Manages the full BLE lifecycle: scan, pair, connect, reconnect.
///
/// Persists the paired device ID via [PrefsManager] so that the app
/// auto-connects on next launch without the user needing to re-scan.
///
/// Also monitors app lifecycle and WiFi connectivity to automatically
/// re-acquire BLE when the user returns home.
class BleConnectionCubit extends Cubit<BleConnectionState>
    with WidgetsBindingObserver {
  BleConnectionCubit({
    required BleRepository bleRepository,
    required PrefsManager prefsManager,
    Connectivity? connectivity,
  })  : _ble = bleRepository,
        _prefs = prefsManager,
        _connectivity = connectivity ?? Connectivity(),
        super(BleConnectionState(
          isBluetoothOn: bleRepository.isAdapterOn,
        )) {
    _statusSub = _ble.connectionStatus.listen(_onStatusChanged);
    _adapterSub = _ble.adapterState.listen(_onAdapterStateChanged);
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub =
        _connectivity.onConnectivityChanged.listen(_onConnectivityChanged);
  }

  final BleRepository _ble;
  final PrefsManager _prefs;
  final Connectivity _connectivity;
  StreamSubscription<BleConnectionStatus>? _statusSub;
  StreamSubscription<bool>? _adapterSub;
  StreamSubscription<List<ScannedDevice>>? _scanSub;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Whether a scan was requested while BT was off (to auto-start later).
  bool _pendingScan = false;

  /// Debounce for probe reconnect attempts.
  DateTime? _lastProbeTime;
  static const _probeDebounce = Duration(seconds: 30);

  // ── Public API ────────────────────────────────────────────────────

  /// Try to connect to the last paired device (called on app start).
  Future<void> tryAutoConnect() async {
    final savedId = _prefs.pairedDeviceId;
    final savedName = _prefs.pairedDeviceName;

    if (savedId == null) return;

    emit(state.copyWith(
      pairedDeviceId: savedId,
      pairedDeviceName: savedName ?? 'GeyserSwitch',
    ));

    // Only attempt connection if BT is on.
    if (_ble.isAdapterOn) {
      await _ble.connect(savedId);
    }
  }

  /// Start scanning for GeyserSwitch devices.
  ///
  /// If BT is off, sets a pending flag so we auto-start when it turns on.
  /// If already connected, this is a no-op.
  void startScan() {
    if (state.isConnected) return;

    // If BT is off, remember that the user wants to scan.
    if (!state.isBluetoothOn) {
      _pendingScan = true;
      emit(state.copyWith(
        scanError: 'Please turn on Bluetooth to scan for devices.',
      ));
      return;
    }

    _pendingScan = false;
    _scanSub?.cancel();
    emit(state.copyWith(scannedDevices: const [], scanError: null));

    _scanSub = _ble.startScan().listen(
      (devices) {
        emit(state.copyWith(scannedDevices: devices));
      },
      onError: (Object e) {
        emit(state.copyWith(scanError: e.toString()));
      },
      onDone: () {
        // Scan finished (timeout reached).  Restore the real status
        // rather than blindly going to 'disconnected'.
        if (state.connectionStatus == BleConnectionStatus.scanning) {
          final realStatus = _ble.currentStatus;
          emit(state.copyWith(connectionStatus: realStatus));
        }
      },
    );
  }

  /// Stop an active scan.
  Future<void> stopScan() async {
    _pendingScan = false;
    await _scanSub?.cancel();
    _scanSub = null;
    await _ble.stopScan();

    // After stopping a scan, restore the true connection status from
    // the BLE repository instead of assuming 'disconnected'.
    final realStatus = _ble.currentStatus;
    if (state.connectionStatus == BleConnectionStatus.scanning) {
      emit(state.copyWith(connectionStatus: realStatus));
    }
  }

  /// Connect to a scanned device and persist as paired.
  Future<void> connectToDevice(ScannedDevice device) async {
    await stopScan();

    await _prefs.setPairedDevice(device.id, device.name);

    emit(state.copyWith(
      pairedDeviceId: device.id,
      pairedDeviceName: device.name,
    ));

    await _ble.connect(device.id);
  }

  /// Disconnect and forget the paired device.
  Future<void> unpair() async {
    await _ble.disconnect();
    await _prefs.clearPairedDevice();
    emit(BleConnectionState(isBluetoothOn: _ble.isAdapterOn));
  }

  /// Manually trigger a reconnect attempt.
  Future<void> reconnect() async {
    final id = state.pairedDeviceId;
    if (id == null) return;
    await _ble.connect(id);
  }

  /// Re-read provisioning info from the device.
  /// Call after provisioning completes to refresh the UI.
  Future<void> refreshDeviceInfo() async {
    if (!state.isConnected) return;
    await _readDeviceInfo();
  }

  // ── BLE re-acquisition ─────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      _probeReconnect('app resumed');
    }
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      _probeReconnect('WiFi joined');
    }
  }

  /// Attempt BLE reconnection if paired, disconnected, idle, and
  /// not probed too recently.
  void _probeReconnect(String reason) {
    if (!state.isPaired || state.isConnected || state.isBusy) return;
    if (!state.isBluetoothOn) return;

    final now = DateTime.now();
    if (_lastProbeTime != null &&
        now.difference(_lastProbeTime!) < _probeDebounce) {
      return;
    }
    _lastProbeTime = now;

    debugPrint('[BLE] Probing reconnect ($reason)');
    reconnect();
  }

  // ── Private ───────────────────────────────────────────────────────

  void _onAdapterStateChanged(bool isOn) {
    emit(state.copyWith(isBluetoothOn: isOn));

    if (isOn) {
      // BT just turned on — if user had requested a scan, start it now.
      if (_pendingScan) {
        startScan();
      }
      // If we have a paired device, try auto-connect.
      else if (state.isPaired && !state.isConnected && !state.isBusy) {
        reconnect();
      }
    }
  }

  void _onStatusChanged(BleConnectionStatus status) {
    emit(state.copyWith(connectionStatus: status));

    // When connection is ready, read provisioning info from the device.
    if (status == BleConnectionStatus.ready) {
      _readDeviceInfo();
    }
  }

  /// Read provisioning state, nickname, and SSID from the device.
  Future<void> _readDeviceInfo() async {
    try {
      // Read provisioning status.
      final statusBytes =
          await _ble.readCharacteristic(GattUuids.provStatus.str);
      final provStatus = statusBytes.isNotEmpty
          ? ProvisioningStatus.fromByte(statusBytes[0])
          : ProvisioningStatus.idle;

      // Read device nickname.
      final nickBytes =
          await _ble.readCharacteristic(GattUuids.provDeviceName.str);
      final nickname =
          nickBytes.isNotEmpty ? utf8.decode(nickBytes) : null;

      // Read stored SSID if WiFi is provisioned.
      String? ssid;
      final isWifi = provStatus == ProvisioningStatus.complete ||
          provStatus == ProvisioningStatus.wifiOk;
      if (isWifi) {
        try {
          final ssidBytes =
              await _ble.readCharacteristic(GattUuids.provWifiCreds.str);
          ssid = ssidBytes.isNotEmpty ? utf8.decode(ssidBytes) : null;
        } catch (_) {
          // Non-fatal — SSID read failed.
        }
      }

      emit(state.copyWith(
        deviceNickname: nickname,
        isWifiProvisioned: isWifi,
        wifiSsid: ssid,
        // Update the paired device name with nickname if available.
        pairedDeviceName: nickname != null && nickname.isNotEmpty
            ? 'GeyserSwitch-$nickname'
            : state.pairedDeviceName,
      ));

      debugPrint('[BLE] Device info: nick="$nickname", '
          'wifi=$isWifi, ssid="$ssid", prov=$provStatus');
    } catch (e) {
      // Non-fatal — device may not have provisioning service yet.
      debugPrint('[BLE] Failed to read device info: $e');
    }
  }

  @override
  Future<void> close() async {
    WidgetsBinding.instance.removeObserver(this);
    await _connectivitySub?.cancel();
    await _scanSub?.cancel();
    await _statusSub?.cancel();
    await _adapterSub?.cancel();
    return super.close();
  }
}
