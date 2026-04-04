import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/ble/gatt_uuids.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../../domain/ble/entities/scanned_device.dart';
import '../../domain/ble/repositories/ble_repository.dart';

/// Production BLE repository backed by [FlutterBluePlus].
///
/// Responsibilities:
/// - Scans for devices advertising the GeyserSwitch service UUID.
/// - Connects, discovers services, and caches characteristic handles.
/// - Auto-reconnects on disconnect with exponential backoff.
/// - Exposes a [connectionStatus] stream for the UI state machine.
class FlutterBluePlusBleRepository implements BleRepository {
  FlutterBluePlusBleRepository();

  // ── Internal state ────────────────────────────────────────────────

  final _statusController = StreamController<BleConnectionStatus>.broadcast();
  BleConnectionStatus _currentStatus = BleConnectionStatus.disconnected;

  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  Timer? _reconnectTimer;

  /// After successful service discovery, we cache characteristic references
  /// here for Phase 2 read/write/notify.
  final Map<Guid, BluetoothCharacteristic> characteristics = {};

  /// Exponential backoff state for reconnection.
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempt = 6; // max ~32s delay
  static const _scanTimeout = Duration(seconds: 12);

  // ── Connection state ──────────────────────────────────────────────

  @override
  Stream<BleConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  BleConnectionStatus get currentStatus => _currentStatus;

  @override
  String? get connectedDeviceId => _device?.remoteId.str;

  @override
  Future<bool> get isAvailable async {
    try {
      return await FlutterBluePlus.isSupported &&
          FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  @override
  bool get isAdapterOn =>
      FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;

  @override
  Stream<bool> get adapterState => FlutterBluePlus.adapterState.map(
        (s) => s == BluetoothAdapterState.on,
      );

  // ── Scanning ──────────────────────────────────────────────────────

  @override
  Stream<List<ScannedDevice>> startScan({Duration timeout = _scanTimeout}) {
    _emitStatus(BleConnectionStatus.scanning);

    // Scan without service UUID filter — some adapters don't report service
    // UUIDs in advertisements. We filter by name prefix in the stream.
    FlutterBluePlus.startScan(timeout: timeout);

    // Map the platform's scan results, filtering to GeyserSwitch* devices.
    return FlutterBluePlus.scanResults.map((results) {
      return results
          .where((r) =>
              r.advertisementData.advName.startsWith('GeyserSwitch'))
          .map((r) => ScannedDevice(
                id: r.device.remoteId.str,
                name: r.advertisementData.advName,
                rssi: r.rssi,
              ))
          .toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi)); // strongest first
    });
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    // Only reset to disconnected if we were scanning AND have no active
    // connection.  If a device is connected, keep the real status.
    if (_currentStatus == BleConnectionStatus.scanning) {
      if (_device != null && characteristics.isNotEmpty) {
        _emitStatus(BleConnectionStatus.ready);
      } else {
        _emitStatus(BleConnectionStatus.disconnected);
      }
    }
  }

  // ── Connection ────────────────────────────────────────────────────

  @override
  Future<void> connect(String deviceId) async {
    // Clean up any previous connection.
    await _cleanupConnection(emitDisconnect: false);

    _device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    _emitStatus(BleConnectionStatus.connecting);

    // Listen to platform connection state.
    _connectionSub = _device!.connectionState.listen(_onConnectionStateChanged);

    try {
      await _device!.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 15),
      );
      // On success, _onConnectionStateChanged will drive the rest.
    } catch (e) {
      _emitStatus(BleConnectionStatus.disconnected);
      _scheduleReconnect();
    }
  }

  @override
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _reconnectAttempt = 0;
    await _cleanupConnection(emitDisconnect: true);
  }

  // ── Characteristic operations (Phase 2) ─────────────────────────

  /// Active notification subscriptions keyed by characteristic UUID string.
  final Map<String, StreamController<Uint8List>> _notifyControllers = {};
  final Map<String, StreamSubscription<List<int>>> _platformSubs = {};

  @override
  Future<Uint8List> readCharacteristic(String characteristicId) async {
    final c = _resolveCharacteristic(characteristicId);
    final bytes = await c.read();
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeCharacteristic(String characteristicId, Uint8List value) async {
    final c = _resolveCharacteristic(characteristicId);
    await c.write(value, withoutResponse: false);
  }

  @override
  Stream<Uint8List> subscribe(String characteristicId) {
    final c = _resolveCharacteristic(characteristicId);

    // Reuse existing controller if already subscribed.
    if (_notifyControllers.containsKey(characteristicId)) {
      return _notifyControllers[characteristicId]!.stream;
    }

    final controller = StreamController<Uint8List>.broadcast(
      onCancel: () => _unsubscribeInternal(characteristicId, c),
    );
    _notifyControllers[characteristicId] = controller;

    c.setNotifyValue(true).then((_) {
      _platformSubs[characteristicId]?.cancel();
      _platformSubs[characteristicId] = c.onValueReceived.listen((bytes) {
        if (!controller.isClosed) {
          controller.add(Uint8List.fromList(bytes));
        }
      });
    });

    return controller.stream;
  }

  @override
  Future<void> unsubscribe(String characteristicId) async {
    final c = characteristics[Guid(characteristicId)];
    if (c != null) {
      await _unsubscribeInternal(characteristicId, c);
    }
  }

  Future<void> _unsubscribeInternal(
      String characteristicId, BluetoothCharacteristic c) async {
    await _platformSubs[characteristicId]?.cancel();
    _platformSubs.remove(characteristicId);
    try {
      await c.setNotifyValue(false);
    } catch (_) {
      // Best effort — device may already be disconnected.
    }
    await _notifyControllers[characteristicId]?.close();
    _notifyControllers.remove(characteristicId);
  }

  BluetoothCharacteristic _resolveCharacteristic(String characteristicId) {
    final c = characteristics[Guid(characteristicId)];
    if (c == null) {
      throw StateError(
        'Characteristic $characteristicId not found. '
        'Is the device connected and services discovered?',
      );
    }
    return c;
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    for (final sub in _platformSubs.values) {
      await sub.cancel();
    }
    _platformSubs.clear();
    for (final controller in _notifyControllers.values) {
      await controller.close();
    }
    _notifyControllers.clear();
    await _cleanupConnection(emitDisconnect: true);
    await _statusController.close();
  }

  // ── Private: connection state handler ─────────────────────────────

  Future<void> _onConnectionStateChanged(BluetoothConnectionState state) async {
    switch (state) {
      case BluetoothConnectionState.connected:
        _reconnectAttempt = 0;
        await _discoverAndCache();

      case BluetoothConnectionState.disconnected:
        characteristics.clear();
        // If we were in a connected state, try to reconnect.
        if (_currentStatus == BleConnectionStatus.ready ||
            _currentStatus == BleConnectionStatus.discoveringServices) {
          _emitStatus(BleConnectionStatus.reconnecting);
          _scheduleReconnect();
        } else {
          _emitStatus(BleConnectionStatus.disconnected);
        }

      default:
        break;
    }
  }

  /// Discover GATT services and cache our characteristic handles.
  ///
  /// Caches characteristics from both the control service (0x01) and
  /// the provisioning service (0x10).
  Future<void> _discoverAndCache() async {
    if (_device == null) return;

    _emitStatus(BleConnectionStatus.discoveringServices);

    try {
      final services = await _device!.discoverServices();

      // UUIDs for the services we care about.
      final targetServices = {GattUuids.service, GattUuids.provService};

      bool foundAny = false;
      for (final svc in services) {
        if (targetServices.contains(svc.serviceUuid)) {
          for (final c in svc.characteristics) {
            characteristics[c.characteristicUuid] = c;
          }
          foundAny = true;
        }
      }

      if (!foundAny) {
        throw StateError('No GeyserSwitch services found');
      }

      _emitStatus(BleConnectionStatus.ready);
    } catch (_) {
      // If service discovery fails, disconnect and retry.
      await _device?.disconnect();
    }
  }

  // ── Private: reconnection with exponential backoff ────────────────

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    if (_reconnectAttempt >= _maxReconnectAttempt || _device == null) {
      _emitStatus(BleConnectionStatus.disconnected);
      _reconnectAttempt = 0;
      return;
    }

    final delay = Duration(seconds: 1 << _reconnectAttempt); // 1, 2, 4, 8, 16, 32s
    _reconnectAttempt++;

    _reconnectTimer = Timer(delay, () async {
      if (_device == null) return;
      _emitStatus(BleConnectionStatus.reconnecting);

      try {
        await _device!.connect(
          autoConnect: false,
          timeout: const Duration(seconds: 10),
        );
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  // ── Private: cleanup ──────────────────────────────────────────────

  Future<void> _cleanupConnection({required bool emitDisconnect}) async {
    _reconnectTimer?.cancel();
    await _connectionSub?.cancel();
    _connectionSub = null;

    try {
      await _device?.disconnect();
    } catch (_) {
      // Best effort.
    }

    characteristics.clear();
    _device = null;

    if (emitDisconnect) {
      _emitStatus(BleConnectionStatus.disconnected);
    }
  }

  // ── Private: status helper ────────────────────────────────────────

  void _emitStatus(BleConnectionStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}
