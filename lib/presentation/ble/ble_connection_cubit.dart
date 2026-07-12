import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/ble/gatt_uuids.dart';
import '../../core/utils/device_id_generator.dart';
import '../../data/ble/ble_owner_auth.dart';
import '../../data/local/prefs_manager.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../../domain/ble/entities/scanned_device.dart';
import '../../domain/ble/repositories/ble_repository.dart';
import '../../domain/provisioning/provisioning_status.dart';
import '../device/device_registry_cubit.dart';

part 'ble_connection_state.dart';

const _sentinel = Object();

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
    required DeviceRegistryCubit deviceRegistry,
    required BleOwnerAuth ownerAuth,
    Connectivity? connectivity,
  })  : _ble = bleRepository,
        _prefs = prefsManager,
        _registry = deviceRegistry,
        _ownerAuth = ownerAuth,
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
  final DeviceRegistryCubit _registry;
  final BleOwnerAuth _ownerAuth;
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

    if (savedId == null || isClosed) return;

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
    if (isClosed || state.isConnected) return;

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
        if (isClosed) return;
        emit(state.copyWith(scannedDevices: devices));
      },
      onError: (Object e) {
        if (isClosed) return;
        emit(state.copyWith(scanError: e.toString()));
      },
      onDone: () {
        if (isClosed) return;
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

    if (isClosed) return;
    final realStatus = _ble.currentStatus;
    if (state.connectionStatus == BleConnectionStatus.scanning) {
      emit(state.copyWith(connectionStatus: realStatus));
    }
  }

  /// Connect to a scanned device and persist as paired.
  Future<void> connectToDevice(ScannedDevice device) async {
    await stopScan();
    if (isClosed) return;

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
    if (isClosed) return;
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
    if (isClosed) return;
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
    if (isClosed) return;
    emit(state.copyWith(connectionStatus: status));

    // When connection is ready, read provisioning info from the device.
    if (status == BleConnectionStatus.ready) {
      _readDeviceInfo();
    }
  }

  /// Read provisioning state, nickname, and SSID from the device.
  Future<void> _readDeviceInfo() async {
    try {
      final statusBytes =
          await _ble.readCharacteristic(GattUuids.provStatus.str);
      if (isClosed) return;
      final provStatus = statusBytes.isNotEmpty
          ? ProvisioningStatus.fromByte(statusBytes[0])
          : ProvisioningStatus.idle;

      final nickBytes =
          await _ble.readCharacteristic(GattUuids.provDeviceName.str);
      if (isClosed) return;
      final nickname =
          nickBytes.isNotEmpty ? utf8.decode(nickBytes) : null;

      String? ssid;
      final isWifi = provStatus == ProvisioningStatus.complete ||
          provStatus == ProvisioningStatus.wifiOk;
      if (isWifi) {
        try {
          final ssidBytes =
              await _ble.readCharacteristic(GattUuids.provWifiCreds.str);
          if (isClosed) return;
          ssid = ssidBytes.isNotEmpty ? utf8.decode(ssidBytes) : null;
        } catch (_) {}
      }

      if (isClosed) return;
      emit(state.copyWith(
        deviceNickname: nickname,
        isWifiProvisioned: isWifi,
        wifiSsid: ssid,
        pairedDeviceName: nickname != null && nickname.isNotEmpty
            ? 'GeyserSwitch-$nickname'
            : state.pairedDeviceName,
      ));

      // Ensure we have an RTDB device ID mapping for this device.
      final bleMac = state.pairedDeviceId;
      if (bleMac != null && _prefs.getRtdbDeviceId(bleMac) == null) {
        // Try reading the stored device ID from the ESP (0x0C).
        // This handles iOS re-pairing where the Core Bluetooth UUID
        // changes but the firmware still knows its RTDB identity.
        String? storedId;
        try {
          final idBytes = await _ble.readCharacteristic(
            GattUuids.storedDeviceId.str,
          );
          if (idBytes.isNotEmpty) {
            storedId = utf8.decode(idBytes);
          }
        } catch (_) {
          // Older firmware without 0x0C — fall through to legacy.
        }

        if (storedId != null && storedId.isNotEmpty) {
          await _prefs.setRtdbDeviceId(bleMac, storedId);
          debugPrint('[BLE] Recovered device ID from ESP: $bleMac → "$storedId"');
        } else {
          // Firmware without 0x0C — derive the ID from the BLE
          // identifier, same as provisioning does. Unlike a shared
          // fallback ID, this stays unique per device.
          final derived = deriveDeviceId(bleMac);
          await _prefs.setRtdbDeviceId(bleMac, derived);
          debugPrint('[BLE] No stored ID on ESP — derived $bleMac → "$derived"');
        }
      }

      // Persist the nickname and update the live device registry so
      // multi-device PageView stays current without needing an app restart.
      String? rtdbId;
      if (bleMac != null) {
        rtdbId = _prefs.getRtdbDeviceId(bleMac)!;
        final nick = (nickname != null && nickname.isNotEmpty)
            ? nickname
            : 'My Geyser';
        await _prefs.setDeviceNickname(rtdbId, nick);

        _registry.addDevice(DeviceInfo(
          rtdbDeviceId: rtdbId,
          bleMac: bleMac,
          nickname: nick,
        ));
      }

      debugPrint('[BLE] Device info: nick="$nickname", '
          'wifi=$isWifi, ssid="$ssid", prov=$provStatus');

      // Owner-lock: prove this phone belongs to the household account
      // so control writes are accepted. Runs after the device ID is
      // resolved (unlock needs it to find the key).
      if (rtdbId != null) {
        await _runOwnerUnlock(rtdbId);
      }
    } catch (e) {
      // Non-fatal — device may not have provisioning service yet.
      debugPrint('[BLE] Failed to read device info: $e');
    }
  }

  /// Run the owner-lock challenge-response and reflect the outcome in
  /// state so the UI can show a "locked" notice when appropriate.
  Future<void> _runOwnerUnlock(String rtdbDeviceId) async {
    final result = await _ownerAuth.unlock(rtdbDeviceId);
    if (isClosed) return;
    emit(state.copyWith(ownerUnlock: result));
    if (result == OwnerUnlockResult.locked ||
        result == OwnerUnlockResult.noKey) {
      debugPrint('[BLE] Owner-lock: control disabled ($result)');
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
