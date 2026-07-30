import 'dart:async';

import '../../core/debug/debug_log.dart';
import '../../domain/ble/ble_connection_status.dart';
import '../../domain/ble/repositories/ble_repository.dart';
import '../../domain/geyser/repositories/geyser_control_repository.dart';
import '../../domain/telemetry/entities/telemetry_record.dart';
import '../../domain/telemetry/repositories/telemetry_repository.dart';
import '../local/prefs_manager.dart';

/// Background service that records telemetry to local storage.
///
/// Lifecycle:
/// 1. Listens to [BleRepository.connectionStatus].
/// 2. When BLE is `ready`, starts a periodic timer that reads the
///    latest geyser snapshot and inserts a [TelemetryRecord] every
///    [recordingInterval] seconds.
/// 3. When BLE disconnects, stops recording.
/// 4. On every start, prunes records older than [retentionDays].
///
/// This class is not a Cubit/Bloc — it's a plain service registered
/// as a singleton in GetIt and started once after login.
class TelemetryRecorder {
  TelemetryRecorder({
    required TelemetryRepository telemetryRepository,
    required GeyserControlRepository geyserControlRepository,
    required BleRepository bleRepository,
    required PrefsManager prefsManager,
    this.recordingInterval = const Duration(seconds: 60),
    this.retentionDays = 7,
  })  : _telemetry = telemetryRepository,
        _geyser = geyserControlRepository,
        _ble = bleRepository,
        _prefs = prefsManager;

  final TelemetryRepository _telemetry;
  final GeyserControlRepository _geyser;
  final BleRepository _ble;
  final PrefsManager _prefs;

  /// How often to record a telemetry entry.
  final Duration recordingInterval;

  /// How many days of data to keep locally.
  final int retentionDays;

  StreamSubscription<BleConnectionStatus>? _bleSub;
  Timer? _recordTimer;
  bool _isRecording = false;

  // ── Public API ────────────────────────────────────────────────────

  /// Start monitoring BLE status and recording when connected.
  /// Idempotent — safe to call again after [stop] (e.g. on re-login).
  void start() {
    if (_bleSub != null) return;
    _bleSub = _ble.connectionStatus.listen(_onBleStatusChanged);

    // If already connected at start time, begin recording.
    if (_ble.currentStatus == BleConnectionStatus.ready) {
      _startRecording();
    }
  }

  /// Stop all recording and clean up.
  Future<void> stop() async {
    _stopRecording();
    await _bleSub?.cancel();
    _bleSub = null;
  }

  // ── Private ───────────────────────────────────────────────────────

  void _onBleStatusChanged(BleConnectionStatus status) {
    if (status == BleConnectionStatus.ready && !_isRecording) {
      _startRecording();
    } else if (status != BleConnectionStatus.ready && _isRecording) {
      _stopRecording();
    }
  }

  void _startRecording() {
    _isRecording = true;

    // Prune old records on every connection (cheap operation).
    _pruneOldRecords();

    // Take an immediate reading, then start the periodic timer.
    _recordReading();
    _recordTimer = Timer.periodic(recordingInterval, (_) => _recordReading());

    debugLog('TelemetryRecorder',
        'Started recording every ${recordingInterval.inSeconds}s');
  }

  void _stopRecording() {
    _recordTimer?.cancel();
    _recordTimer = null;
    _isRecording = false;

    debugLog('TelemetryRecorder', 'Stopped recording');
  }

  Future<void> _recordReading() async {
    try {
      final bleMac = _ble.connectedDeviceId;
      if (bleMac == null) return;
      final deviceId = _prefs.getRtdbDeviceId(bleMac);
      if (deviceId == null) return;

      // Use the cached snapshot — no BLE reads.  The notification
      // streams keep it up to date in real time, so there's no need
      // to poll the device and risk interfering with notifications.
      final snapshot = _geyser.lastSnapshot;

      final record = TelemetryRecord(
        deviceId: deviceId,
        timestamp: DateTime.now().toUtc(),
        temperature: snapshot.temperature,
        isOn: snapshot.isOn,
        minTemp: snapshot.minTemp,
        maxTemp: snapshot.maxTemp,
      );

      await _telemetry.insert(record);

      debugLog('TelemetryRecorder',
          'Recorded: ${snapshot.temperature}°C, on=${snapshot.isOn}');
    } catch (e) {
      debugLog('TelemetryRecorder', 'Error recording: $e');
    }
  }

  Future<void> _pruneOldRecords() async {
    try {
      final pruned = await _telemetry.pruneOlderThan(retentionDays: retentionDays);
      if (pruned > 0) {
        debugLog('TelemetryRecorder',
            'Pruned $pruned records older than $retentionDays days');
      }
    } catch (e) {
      debugLog('TelemetryRecorder', 'Error pruning: $e');
    }
  }
}
