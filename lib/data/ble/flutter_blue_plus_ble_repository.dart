import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
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

  /// Firmware advertises `GeyserSwitch`, `GeyserSwitch-Setup` or
  /// `GeyserSwitch-<nickname>`, and sets the same string as its GAP name.
  static const _namePrefix = 'GeyserSwitch';

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

    final controller = StreamController<List<ScannedDevice>>();

    // Two sources, because scanning alone cannot see everything. A device
    // the OS is already connected to has stopped advertising, so it is
    // absent from every scan result — see [_systemConnectedDevices].
    var advertised = <ScannedDevice>[];
    var connected = <ScannedDevice>[];

    void emitMerged() {
      if (controller.isClosed) return;
      controller.add(mergeDiscovered(
        advertised: advertised,
        connected: connected,
      ));
    }

    // Seed from the platform's connected list before the first
    // advertisement arrives, so a silent device appears immediately
    // rather than after the scan times out with nothing.
    _systemConnectedDevices().then((devices) {
      if (devices.isEmpty) return;
      connected = devices;
      emitMerged();
    });

    // Map the platform's scan results, filtering to GeyserSwitch* devices.
    // Scan without service UUID filter — some adapters don't report service
    // UUIDs in advertisements. We filter by name prefix in the stream.
    final resultsSub = FlutterBluePlus.scanResults.map((results) {
      return results
          .where((r) => r.advertisementData.advName.startsWith(_namePrefix))
          .map((r) => ScannedDevice(
                id: r.device.remoteId.str,
                name: r.advertisementData.advName,
                rssi: r.rssi,
              ))
          .toList();
    }).listen(
      (devices) {
        advertised = devices;
        emitMerged();
      },
      onError: (Object e) {
        if (!controller.isClosed) controller.addError(e);
      },
    );

    // Close our stream when the platform scan actually ends (the 12 s
    // platform timeout) — scanResults is a broadcast stream that never
    // closes, so without this the listener's onDone never fired and
    // the UI stayed in "scanning" until the user tapped Stop.
    //
    // `started` is armed by the startScan FUTURE, not by isScanning:
    // the plugin emits true→false synchronously around a failed start
    // (and around restarting an in-flight scan), so gating on the
    // stream would close this controller before catchError could
    // report the error — swallowing exactly the permission-denied
    // case this exists to surface.
    var started = false;
    final scanningSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!scanning && started && !controller.isClosed) {
        _resetScanStatus();
        controller.close();
      }
    });

    // Surface start failures (Android 12+ scan permission denied,
    // adapter races). Previously fire-and-forget: the error was an
    // unhandled zone exception, scanResults never errored, and the UI
    // showed an empty "Scanning…" list forever.
    FlutterBluePlus.startScan(timeout: timeout).then((_) {
      started = true;
    }).catchError((Object e) {
      if (!controller.isClosed) {
        controller.addError(e);
        _resetScanStatus();
        controller.close();
      }
    });

    controller.onCancel = () async {
      await resultsSub.cancel();
      await scanningSub.cancel();
    };

    return controller.stream;
  }

  /// Combine advertised and already-connected devices into one list.
  ///
  /// Pure so the ordering rules can be tested without the platform: the
  /// live path around it is entirely FlutterBluePlus statics.
  ///
  /// An id present in both wins as the advertised entry, because that one
  /// carries a signal reading measured this session.
  @visibleForTesting
  static List<ScannedDevice> mergeDiscovered({
    required List<ScannedDevice> advertised,
    required List<ScannedDevice> connected,
  }) {
    final byId = <String, ScannedDevice>{
      for (final d in connected) d.id: d,
      for (final d in advertised) d.id: d,
    };
    return byId.values.toList()
      ..sort((a, b) {
        // Already-connected first: actionable, and with no signal reading
        // there is nothing to rank them by against the rest.
        if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
        return (b.rssi ?? -128).compareTo(a.rssi ?? -128); // strongest first
      });
  }

  /// GeyserSwitch devices the OS already holds a connection to.
  ///
  /// These are invisible to scanning, and not because of any filtering:
  /// the firmware does not restart advertising after a successful connect
  /// (`ble_init.c` only re-advertises on disconnect or a failed connect),
  /// so a connected unit is radio-silent. On iOS this bites hardest,
  /// because CoreBluetooth connections belong to the system daemon rather
  /// than the app process and therefore outlive an app relaunch — leaving
  /// a provisioned device that the user can neither see nor reach.
  ///
  /// Enrichment only: a failure here must never break the scan.
  Future<List<ScannedDevice>> _systemConnectedDevices() async {
    try {
      final devices = await FlutterBluePlus.systemDevices([GattUuids.service]);

      // `withServices` is honoured on iOS (required there, for privacy)
      // but IGNORED on Android, where this returns every connected
      // device — headphones, watches, car kits. The firmware sets its GAP
      // name to the same GeyserSwitch* string it advertises, so the name
      // prefix does the narrowing there. On iOS the service filter is
      // authoritative and the name is not required to be cached.
      final ours = Platform.isAndroid
          ? devices.where((d) => d.platformName.startsWith(_namePrefix))
          : devices;

      return ours
          .map((d) => ScannedDevice(
                id: d.remoteId.str,
                name: d.platformName.isEmpty ? _namePrefix : d.platformName,
                isConnected: true,
              ))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// After a scan ends (naturally or on failure), restore the real
  /// connection status — mirrors [stopScan].
  void _resetScanStatus() {
    if (_currentStatus != BleConnectionStatus.scanning) return;
    if (_device != null && characteristics.isNotEmpty) {
      _emitStatus(BleConnectionStatus.ready);
    } else {
      _emitStatus(BleConnectionStatus.disconnected);
    }
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

  static const _gattRetries = 3;
  static const _gattRetryDelay = Duration(milliseconds: 600);

  /// Retry wrapper for BLE operations that may fail transiently while
  /// the link is still encrypting after Just Works pairing.
  Future<T> _withRetry<T>(Future<T> Function() op) async {
    for (int attempt = 1; attempt <= _gattRetries; attempt++) {
      try {
        return await op();
      } catch (e) {
        if (attempt == _gattRetries) rethrow;
        await Future<void>.delayed(_gattRetryDelay);
      }
    }
    throw StateError('unreachable');
  }

  @override
  Future<Uint8List> readCharacteristic(String characteristicId) async {
    final c = _resolveCharacteristic(characteristicId);
    final bytes = await _withRetry(() => c.read());
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> writeCharacteristic(String characteristicId, Uint8List value,
      {bool allowLongWrite = false, bool retries = true}) async {
    final c = _resolveCharacteristic(characteristicId);
    Future<void> write() => c.write(
          value,
          withoutResponse: false,
          allowLongWrite: allowLongWrite,
        );
    if (!retries) {
      await write();
      return;
    }
    await _withRetry(write);
  }

  @override
  Stream<Uint8List> subscribe(String characteristicId) {
    final c = _resolveCharacteristic(characteristicId);

    if (_notifyControllers.containsKey(characteristicId)) {
      return _notifyControllers[characteristicId]!.stream;
    }

    final controller = StreamController<Uint8List>.broadcast(
      onCancel: () => _unsubscribeInternal(characteristicId, c),
    );
    _notifyControllers[characteristicId] = controller;

    _withRetry(() => c.setNotifyValue(true)).then((_) {
      _platformSubs[characteristicId]?.cancel();
      _platformSubs[characteristicId] = c.onValueReceived.listen((bytes) {
        if (!controller.isClosed) {
          controller.add(Uint8List.fromList(bytes));
        }
      });
    }).catchError((e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
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
