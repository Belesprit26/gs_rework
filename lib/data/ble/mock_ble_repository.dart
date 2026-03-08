import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../../core/ble/gatt_uuids.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../../domain/ble/entities/scanned_device.dart';
import '../../domain/ble/repositories/ble_repository.dart';

/// A fake BLE repository for development and testing without hardware.
///
/// Simulates:
/// - Scan discovering a fake device after a short delay.
/// - Connection with a realistic delay.
/// - Service discovery.
/// - Auto-reconnect on simulated disconnection.
/// - Phase 2: read/write/notify with in-memory geyser state.
///
/// Toggle [_useMockBle] in DI to switch between this and the real impl.
class MockBleRepository implements BleRepository {
  MockBleRepository();

  // ── Internal state ────────────────────────────────────────────────

  final _statusController = StreamController<BleConnectionStatus>.broadcast();
  BleConnectionStatus _currentStatus = BleConnectionStatus.disconnected;
  String? _connectedId;

  static const _fakeDevice = ScannedDevice(
    id: 'GS:MOCK:AA:BB:CC:DD',
    name: 'GeyserSwitch-Mock',
    rssi: -42,
  );

  // ── Simulated geyser state ────────────────────────────────────────

  /// Temperature in °C × 100 as int16 (e.g. 4250 = 42.50°C).
  int _mockTempRaw = 4250;

  /// 0x00 = off, 0x01 = on.
  int _mockGeyserState = 0;

  /// [minTemp, maxTemp, autoReheat] as uint8.
  final List<int> _mockTempLimits = [30, 60, 0];

  /// Timer config: 5 timers × 4 bytes [is_preset, enabled, hour, minute].
  final List<int> _mockTimerConfig = [
    1, 0, 4, 0,   // Preset 1: 04:00, disabled
    1, 0, 6, 0,   // Preset 2: 06:00, disabled
    1, 0, 15, 0,  // Preset 3: 15:00, disabled
    1, 0, 17, 0,  // Preset 4: 17:00, disabled
    0, 0, 6, 0,   // Custom:   06:00, disabled
  ];

  /// Firmware version.
  static const _mockFirmware = '0.2.0-mock';

  /// Active notification streams.
  final Map<String, StreamController<Uint8List>> _notifyControllers = {};
  Timer? _tempSimTimer;

  // ── Connection state ──────────────────────────────────────────────

  @override
  Stream<BleConnectionStatus> get connectionStatus => _statusController.stream;

  @override
  BleConnectionStatus get currentStatus => _currentStatus;

  @override
  String? get connectedDeviceId => _connectedId;

  @override
  Future<bool> get isAvailable async => true;

  @override
  bool get isAdapterOn => true;

  @override
  Stream<bool> get adapterState => Stream.value(true);

  // ── Scanning ──────────────────────────────────────────────────────

  @override
  Stream<List<ScannedDevice>> startScan({Duration timeout = const Duration(seconds: 8)}) {
    _emitStatus(BleConnectionStatus.scanning);

    final controller = StreamController<List<ScannedDevice>>();

    // Simulate finding the device after 1.5s.
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (!controller.isClosed) {
        controller.add(const [_fakeDevice]);
      }
    });

    // Auto-stop after timeout.
    Future.delayed(timeout, () {
      if (!controller.isClosed) {
        controller.close();
        if (_currentStatus == BleConnectionStatus.scanning) {
          _emitStatus(BleConnectionStatus.disconnected);
        }
      }
    });

    return controller.stream;
  }

  @override
  Future<void> stopScan() async {
    if (_currentStatus == BleConnectionStatus.scanning) {
      _emitStatus(BleConnectionStatus.disconnected);
    }
  }

  // ── Connection ────────────────────────────────────────────────────

  @override
  Future<void> connect(String deviceId) async {
    _emitStatus(BleConnectionStatus.connecting);
    await Future.delayed(const Duration(milliseconds: 800));

    _emitStatus(BleConnectionStatus.discoveringServices);
    await Future.delayed(const Duration(milliseconds: 600));

    _connectedId = deviceId;
    _emitStatus(BleConnectionStatus.ready);
  }

  @override
  Future<void> disconnect() async {
    _stopTempSimulation();
    _connectedId = null;
    _emitStatus(BleConnectionStatus.disconnected);
  }

  // ── Characteristic operations (Phase 2) ───────────────────────────

  @override
  Future<Uint8List> readCharacteristic(String characteristicId) async {
    // Simulate ~20ms BLE read latency.
    await Future.delayed(const Duration(milliseconds: 20));
    return _resolveRead(characteristicId);
  }

  @override
  Future<void> writeCharacteristic(String characteristicId, Uint8List value) async {
    // Simulate ~30ms BLE write latency.
    await Future.delayed(const Duration(milliseconds: 30));
    _resolveWrite(characteristicId, value);
  }

  @override
  Stream<Uint8List> subscribe(String characteristicId) {
    if (_notifyControllers.containsKey(characteristicId)) {
      return _notifyControllers[characteristicId]!.stream;
    }

    final controller = StreamController<Uint8List>.broadcast(
      onCancel: () => _notifyControllers.remove(characteristicId),
    );
    _notifyControllers[characteristicId] = controller;

    // Start temperature simulation if subscribing to temperature.
    if (characteristicId == GattUuids.temperature.str) {
      _startTempSimulation();
    }

    return controller.stream;
  }

  @override
  Future<void> unsubscribe(String characteristicId) async {
    if (characteristicId == GattUuids.temperature.str) {
      _stopTempSimulation();
    }
    await _notifyControllers[characteristicId]?.close();
    _notifyControllers.remove(characteristicId);
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    _stopTempSimulation();
    _connectedId = null;
    for (final c in _notifyControllers.values) {
      await c.close();
    }
    _notifyControllers.clear();
    await _statusController.close();
  }

  // ── Private: mock data resolution ─────────────────────────────────

  Uint8List _resolveRead(String characteristicId) {
    if (characteristicId == GattUuids.temperature.str) {
      // int16 little-endian.
      final bd = ByteData(2)..setInt16(0, _mockTempRaw, Endian.little);
      return bd.buffer.asUint8List();
    }
    if (characteristicId == GattUuids.geyserState.str) {
      return Uint8List.fromList([_mockGeyserState]);
    }
    if (characteristicId == GattUuids.tempLimits.str) {
      return Uint8List.fromList(_mockTempLimits);
    }
    if (characteristicId == GattUuids.timerConfig.str) {
      return Uint8List.fromList(_mockTimerConfig);
    }
    if (characteristicId == GattUuids.deviceInfo.str) {
      return Uint8List.fromList(_mockFirmware.codeUnits);
    }
    // Provisioning characteristics — return sensible defaults.
    if (characteristicId == GattUuids.provStatus.str) {
      return Uint8List.fromList([0]); // PROV_IDLE
    }
    if (characteristicId == GattUuids.provDeviceName.str) {
      return Uint8List.fromList('Mock'.codeUnits);
    }
    if (characteristicId == GattUuids.provWifiCreds.str) {
      return Uint8List(0); // No SSID stored.
    }
    // Event & telemetry buffers — return empty.
    if (characteristicId == GattUuids.deviceEvents.str) {
      return Uint8List(0);
    }
    if (characteristicId == GattUuids.telemetryBuffer.str) {
      return Uint8List(0);
    }
    throw StateError('Unknown characteristic: $characteristicId');
  }

  void _resolveWrite(String characteristicId, Uint8List value) {
    if (characteristicId == GattUuids.geyserState.str) {
      _mockGeyserState = value[0];
      // Notify listener of new state.
      _notifyCharacteristic(characteristicId, Uint8List.fromList([_mockGeyserState]));
      return;
    }
    if (characteristicId == GattUuids.tempLimits.str) {
      _mockTempLimits[0] = value[0];
      _mockTempLimits[1] = value[1];
      if (value.length > 2) _mockTempLimits[2] = value[2];
      return;
    }
    if (characteristicId == GattUuids.timerConfig.str) {
      _mockTimerConfig.clear();
      _mockTimerConfig.addAll(value);
      return;
    }
    if (characteristicId == GattUuids.timeSync.str) {
      // Accept and ignore — mock doesn't need time sync.
      return;
    }
    // Provisioning writes — accept silently.
    if (characteristicId == GattUuids.provWifiCreds.str ||
        characteristicId == GattUuids.provUserBind.str ||
        characteristicId == GattUuids.provDeviceName.str) {
      return;
    }
    // Buffer acknowledge — accept silently.
    if (characteristicId == GattUuids.bufferAck.str) {
      return;
    }
    throw StateError('Write not supported for: $characteristicId');
  }

  /// Push a notification to listeners of a characteristic.
  void _notifyCharacteristic(String characteristicId, Uint8List value) {
    final controller = _notifyControllers[characteristicId];
    if (controller != null && !controller.isClosed) {
      controller.add(value);
    }
  }

  // ── Private: temperature simulation ───────────────────────────────

  /// Simulates temperature drift every 3 seconds (±0.5°C).
  void _startTempSimulation() {
    _tempSimTimer?.cancel();
    final rng = Random();
    _tempSimTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      // Drift between -50 and +50 (i.e. ±0.50°C).
      final drift = rng.nextInt(101) - 50;
      _mockTempRaw = (_mockTempRaw + drift).clamp(2000, 6500); // 20°C – 65°C

      // When geyser is on, bias upward; when off, bias downward.
      if (_mockGeyserState == 1) {
        _mockTempRaw = (_mockTempRaw + 30).clamp(2000, 6500);
      } else {
        _mockTempRaw = (_mockTempRaw - 15).clamp(2000, 6500);
      }

      final bd = ByteData(2)..setInt16(0, _mockTempRaw, Endian.little);
      _notifyCharacteristic(
        GattUuids.temperature.str,
        bd.buffer.asUint8List(),
      );
    });
  }

  void _stopTempSimulation() {
    _tempSimTimer?.cancel();
    _tempSimTimer = null;
  }

  // ── Private ───────────────────────────────────────────────────────

  void _emitStatus(BleConnectionStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}
