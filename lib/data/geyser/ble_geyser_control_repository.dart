import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../core/ble/gatt_uuids.dart';
import '../../domain/ble/repositories/ble_repository.dart';
import '../../domain/geyser/entities/geyser_snapshot.dart';
import '../../domain/geyser/repositories/geyser_control_repository.dart';

/// Translates between [GeyserControlRepository] domain types and raw BLE bytes.
///
/// This is the only place where the byte-level protocol is defined:
///
/// | Characteristic  | Format                                          |
/// |-----------------|-------------------------------------------------|
/// | temperature     | int16 LE — °C × 100 (e.g. 4250 = 42.50°)       |
/// | geyserState     | uint8 — 0 = off, 1 = on                         |
/// | tempLimits      | [uint8 min, uint8 max, uint8 auto_reheat]       |
/// | timerConfig     | N × [is_preset, enabled, hour, minute]          |
/// | deviceInfo      | UTF-8 string                                    |
/// | timeSync        | uint32 LE — Unix timestamp (write only)         |
class BleGeyserControlRepository implements GeyserControlRepository {
  BleGeyserControlRepository({required BleRepository bleRepository})
      : _ble = bleRepository;

  final BleRepository _ble;

  StreamSubscription<Uint8List>? _tempSub;
  StreamSubscription<Uint8List>? _stateSub;

  final _tempController = StreamController<double>.broadcast();
  final _stateController = StreamController<bool>.broadcast();

  GeyserSnapshot _lastSnapshot = const GeyserSnapshot();

  @override
  GeyserSnapshot get lastSnapshot => _lastSnapshot;

  // ── Read ──────────────────────────────────────────────────────────

  @override
  Future<GeyserSnapshot> readSnapshot() async {
    final results = await Future.wait([
      _ble.readCharacteristic(GattUuids.temperature.str),
      _ble.readCharacteristic(GattUuids.geyserState.str),
      _ble.readCharacteristic(GattUuids.tempLimits.str),
      _ble.readCharacteristic(GattUuids.timerConfig.str),
      _ble.readCharacteristic(GattUuids.deviceInfo.str),
    ]);

    final limitsBytes = results[2];

    _lastSnapshot = GeyserSnapshot(
      temperature: _decodeTemperature(results[0]),
      isOn: _decodeGeyserState(results[1]),
      minTemp: limitsBytes.isNotEmpty ? limitsBytes[0] : 30,
      maxTemp: limitsBytes.length > 1 ? limitsBytes[1] : 60,
      autoReheat: limitsBytes.length > 2 ? limitsBytes[2] == 1 : false,
      timers: _decodeTimers(results[3]),
      firmwareVersion: utf8.decode(results[4]),
    );
    return _lastSnapshot;
  }

  // ── Streams ───────────────────────────────────────────────────────

  @override
  Stream<double> get temperatureStream => _tempController.stream;

  @override
  Stream<bool> get geyserStateStream => _stateController.stream;

  // ── Write commands ────────────────────────────────────────────────

  @override
  Future<void> setGeyserState(bool on) async {
    await _ble.writeCharacteristic(
      GattUuids.geyserState.str,
      Uint8List.fromList([on ? 0x01 : 0x00]),
    );
  }

  @override
  Future<void> setTempLimits({
    required int min,
    required int max,
    required bool autoReheat,
  }) async {
    await _ble.writeCharacteristic(
      GattUuids.tempLimits.str,
      Uint8List.fromList([
        min.clamp(0, 255),
        max.clamp(0, 255),
        autoReheat ? 1 : 0,
      ]),
    );
  }

  @override
  Future<void> setTimers(List<GeyserTimer> timers) async {
    final bytes = <int>[];
    for (final t in timers) {
      bytes.addAll([
        t.isPreset ? 1 : 0,
        t.enabled ? 1 : 0,
        t.hour,
        t.minute,
      ]);
    }
    await _ble.writeCharacteristic(
      GattUuids.timerConfig.str,
      Uint8List.fromList(bytes),
    );
  }

  @override
  Future<void> pushPhoneTime() async {
    final now = DateTime.now().toUtc();
    final unixSeconds = now.millisecondsSinceEpoch ~/ 1000;

    // Pack as uint32 LE.
    final bd = ByteData(4)..setUint32(0, unixSeconds, Endian.little);
    await _ble.writeCharacteristic(
      GattUuids.timeSync.str,
      bd.buffer.asUint8List(),
    );
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  Future<void> startListening() async {
    // Subscribe to temperature notifications.
    _tempSub = _ble.subscribe(GattUuids.temperature.str).listen((bytes) {
      final temp = _decodeTemperature(bytes);
      _lastSnapshot = _lastSnapshot.copyWith(temperature: temp);
      if (!_tempController.isClosed) {
        _tempController.add(temp);
      }
    });

    // Subscribe to geyser state notifications.
    _stateSub = _ble.subscribe(GattUuids.geyserState.str).listen((bytes) {
      final isOn = _decodeGeyserState(bytes);
      _lastSnapshot = _lastSnapshot.copyWith(isOn: isOn);
      if (!_stateController.isClosed) {
        _stateController.add(isOn);
      }
    });
  }

  @override
  Future<void> stopListening() async {
    await _tempSub?.cancel();
    _tempSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _ble.unsubscribe(GattUuids.temperature.str);
    await _ble.unsubscribe(GattUuids.geyserState.str);
  }

  // ── Private: byte decoders ────────────────────────────────────────

  /// Decode int16 LE → °C.
  static double _decodeTemperature(Uint8List bytes) {
    if (bytes.length < 2) return 0;
    final bd = ByteData.sublistView(bytes);
    return bd.getInt16(0, Endian.little) / 100.0;
  }

  /// Decode uint8 → bool.
  static bool _decodeGeyserState(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    return bytes[0] == 0x01;
  }

  /// Decode N × 4-byte timer entries [is_preset, enabled, hour, minute].
  static List<GeyserTimer> _decodeTimers(Uint8List bytes) {
    final timers = <GeyserTimer>[];
    for (var i = 0; i + 3 < bytes.length; i += 4) {
      timers.add(GeyserTimer(
        isPreset: bytes[i] == 1,
        enabled: bytes[i + 1] == 1,
        hour: bytes[i + 2],
        minute: bytes[i + 3],
      ));
    }
    return timers;
  }
}
