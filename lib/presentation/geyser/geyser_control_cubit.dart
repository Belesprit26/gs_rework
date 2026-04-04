import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/ble/ble_connection_status.dart';
import '../../domain/ble/repositories/ble_repository.dart';
import '../../domain/geyser/entities/geyser_live.dart';
import '../../domain/geyser/entities/geyser_settings.dart';
import '../../domain/geyser/entities/geyser_snapshot.dart';
import '../../domain/geyser/repositories/geyser_control_repository.dart';
import '../../domain/geyser/repositories/rtdb_repository.dart';
import '../../domain/geyser/timer_presets.dart';

part 'geyser_control_state.dart';

const _sentinel = Object();

/// Manages all geyser data & commands for the UI.
///
/// Supports two modes, switching automatically:
/// - **Local (BLE):** When BLE is connected — reads/writes via GATT.
/// - **Remote (RTDB):** When BLE is disconnected — reads from
///   `live/{did}`, writes to `set/{did}`.
///
/// BLE always takes priority.  Remote mode activates as a fallback
/// when BLE drops, and deactivates when BLE reconnects.
class GeyserControlCubit extends Cubit<GeyserControlState> {
  GeyserControlCubit({
    required GeyserControlRepository geyserControlRepository,
    required BleRepository bleRepository,
    RtdbRepository? rtdbRepository,
    String deviceId = 'g1',
  })  : _geyser = geyserControlRepository,
        _ble = bleRepository,
        _rtdb = rtdbRepository,
        _deviceId = deviceId,
        super(const GeyserControlState()) {
    _bleSub = _ble.connectionStatus.listen(_onBleStatusChanged);

    // If BLE isn't connected at construction time, start remote
    // sync right away so the user sees data immediately.
    if (_rtdb != null) {
      emit(state.copyWith(mode: GeyserMode.remote, deviceOffline: true));
      _startRemoteSync();
    }
  }

  final GeyserControlRepository _geyser;
  final BleRepository _ble;
  final RtdbRepository? _rtdb;
  final String _deviceId;

  StreamSubscription<BleConnectionStatus>? _bleSub;
  StreamSubscription<double>? _tempSub;
  StreamSubscription<bool>? _stateSub;

  // Remote mode streams
  StreamSubscription<GeyserLive>? _liveSub;
  StreamSubscription<GeyserSettings>? _settingsSub;
  Timer? _heartbeat;
  bool _bleReady = false;

  static const _offlineThreshold = Duration(seconds: 60);

  /// True when BLE is disconnected and an RTDB repo is available.
  bool get _useRemote => !_bleReady && _rtdb != null;

  // ── Commands ──────────────────────────────────────────────────────

  /// Toggle the geyser on/off.
  ///
  /// **Remote mode:** Writes `set/{did}/on`, then waits up to 2 s for
  /// the ESP to confirm in `live/{did}/on`.  If not confirmed, reverts
  /// the optimistic UI update and sets [GeyserControlState.error].
  ///
  /// **Local mode:** Sends BLE write; confirmation comes via the
  /// geyser-state notification stream.
  Future<void> toggleGeyser() async {
    if (isClosed || state.isBusy) return;
    final desired = !state.snapshot.isOn;

    emit(state.copyWith(
      isBusy: true,
      error: null,
      snapshot: state.snapshot.copyWith(isOn: desired),
    ));

    try {
      if (_useRemote) {
        final confirmed = await _rtdb!.toggleRelay(
          _deviceId,
          desired,
          timeout: const Duration(seconds: 10),
        );
        if (isClosed) return;
        if (!confirmed) {
          emit(state.copyWith(
            isBusy: false,
            snapshot: state.snapshot.copyWith(isOn: !desired),
            error: 'Command timed out — device may be offline',
          ));
          return;
        }
      } else {
        await _geyser.setGeyserState(desired);
        if (isClosed) return;
      }
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
        isBusy: false,
        snapshot: state.snapshot.copyWith(isOn: !desired),
        error: e.toString(),
      ));
      return;
    }

    emit(state.copyWith(isBusy: false));
  }

  /// Set temperature limits and auto-reheat flag.
  Future<void> setTempLimits({
    required int min,
    required int max,
    required bool autoReheat,
  }) async {
    if (isClosed) return;
    emit(state.copyWith(error: null));
    try {
      if (_useRemote) {
        await _rtdb!.writeSettings(_deviceId, {
          'min': min,
          'max': max,
          'ar': autoReheat,
        });
      } else {
        await _geyser.setTempLimits(
            min: min, max: max, autoReheat: autoReheat);
      }
      if (isClosed) return;
      emit(state.copyWith(
        snapshot: state.snapshot.copyWith(
          minTemp: min,
          maxTemp: max,
          autoReheat: autoReheat,
        ),
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(error: e.toString()));
    }
  }

  /// Write timer configuration.
  Future<void> setTimers(List<GeyserTimer> timers) async {
    if (isClosed) return;
    emit(state.copyWith(error: null));
    try {
      if (_useRemote) {
        int mask = 0;
        int customMinutes = 0;
        for (int i = 0; i < timers.length; i++) {
          final t = timers[i];
          if (t.isPreset && t.enabled) mask |= (1 << i);
          if (!t.isPreset && t.enabled) {
            customMinutes = t.hour * 60 + t.minute;
          }
        }
        await _rtdb!.writeSettings(_deviceId, {
          'tmask': mask,
          'tcust': customMinutes,
        });
      } else {
        await _geyser.setTimers(timers);
      }
      if (isClosed) return;
      emit(state.copyWith(
        snapshot: state.snapshot.copyWith(timers: timers),
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(error: e.toString()));
    }
  }

  /// Force-refresh the full snapshot from the device.
  Future<void> refreshSnapshot() async {
    if (_useRemote) {
      await _fetchRemoteSnapshot();
    } else {
      await _fetchInitialSnapshot();
    }
  }

  // ── Remote mode (RTDB) ───────────────────────────────────────────

  void _startRemoteSync() {
    final rtdb = _rtdb;
    if (rtdb == null) return;

    _liveSub?.cancel();
    _liveSub = rtdb.watchLive(_deviceId).listen((live) {
      if (isClosed || _bleReady) return;
      final isStale = live.lastSeen == null ||
          DateTime.now().difference(live.lastSeen!) > _offlineThreshold;
      if (state.isBusy) {
        emit(state.copyWith(
          snapshot: state.snapshot.copyWith(temperature: live.temperature),
          deviceLastSeen: live.lastSeen,
          deviceOffline: isStale,
        ));
      } else {
        emit(state.copyWith(
          snapshot: state.snapshot.copyWith(
            temperature: live.temperature,
            isOn: live.isOn,
          ),
          isBusy: false,
          isLoading: false,
          error: null,
          deviceLastSeen: live.lastSeen,
          deviceOffline: isStale,
        ));
      }
    });

    _settingsSub?.cancel();
    _settingsSub = rtdb.watchSettings(_deviceId).listen((settings) {
      if (isClosed || _bleReady) return;
      emit(state.copyWith(
        snapshot: state.snapshot.copyWith(
          minTemp: settings.minTemp,
          maxTemp: settings.maxTemp,
          autoReheat: settings.autoReheat,
          timers: _timersFromSettings(settings),
        ),
      ));
    });

    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isClosed) return;
      _checkDeviceStaleness();
    });

    _fetchRemoteSnapshot();
    rtdb.touchAppActive().catchError((_) {});
  }

  void _checkDeviceStaleness() {
    if (isClosed) return;
    final lastSeen = state.deviceLastSeen;
    final isStale = lastSeen == null ||
        DateTime.now().difference(lastSeen) > _offlineThreshold;
    if (isStale != state.deviceOffline) {
      emit(state.copyWith(deviceOffline: isStale));
    }
  }

  Future<void> _stopRemoteSync() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _liveSub?.cancel();
    _liveSub = null;
    await _settingsSub?.cancel();
    _settingsSub = null;
  }

  Future<void> _fetchRemoteSnapshot() async {
    final rtdb = _rtdb;
    if (rtdb == null || isClosed) return;
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final settings = await rtdb.readSettings(_deviceId);
      if (isClosed) return;
      emit(state.copyWith(
        isLoading: false,
        snapshot: state.snapshot.copyWith(
          isOn: settings.on,
          minTemp: settings.minTemp,
          maxTemp: settings.maxTemp,
          autoReheat: settings.autoReheat,
          timers: _timersFromSettings(settings),
        ),
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  List<GeyserTimer> _timersFromSettings(GeyserSettings settings) {
    final timers = <GeyserTimer>[];
    for (int i = 0; i < kPresetTimers.length; i++) {
      timers.add(GeyserTimer(
        hour: kPresetTimers[i].hour,
        minute: kPresetTimers[i].minute,
        enabled: (settings.timerMask & (1 << i)) != 0,
        isPreset: true,
      ));
    }
    timers.add(GeyserTimer(
      hour: settings.customTimer ~/ 60,
      minute: settings.customTimer % 60,
      enabled: settings.customTimer > 0,
      isPreset: false,
    ));
    return timers;
  }

  // ── Private: BLE status listener ──────────────────────────────────

  Future<void> _onBleStatusChanged(BleConnectionStatus status) async {
    if (isClosed) return;
    emit(state.copyWith(bleStatus: status));

    if (status == BleConnectionStatus.ready) {
      _bleReady = true;
      await _stopRemoteSync();
      if (isClosed) return;
      emit(state.copyWith(mode: GeyserMode.ble));
      await _fetchInitialSnapshot();
      if (isClosed) return;
      await _pushPhoneTime();
      if (isClosed) return;
      await _startStreams();
    } else if (status == BleConnectionStatus.disconnected ||
        status == BleConnectionStatus.reconnecting) {
      _bleReady = false;
      await _stopStreams();
      if (isClosed) return;
      if (state.mode == GeyserMode.ble) {
        if (_rtdb != null) {
          emit(state.copyWith(mode: GeyserMode.remote, deviceOffline: true));
          _startRemoteSync();
        } else {
          emit(state.copyWith(mode: GeyserMode.offline));
        }
      }
    }
  }

  Future<void> _fetchInitialSnapshot() async {
    if (isClosed) return;
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final snapshot = await _geyser.readSnapshot();
      if (isClosed) return;
      emit(state.copyWith(snapshot: snapshot, isLoading: false));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  /// Push the phone's current time to the ESP32 once per connection.
  Future<void> _pushPhoneTime() async {
    try {
      await _geyser.pushPhoneTime();
    } catch (e) {
      // Non-fatal — old firmware may not have the time sync characteristic.
    }
  }

  Future<void> _startStreams() async {
    await _geyser.startListening();
    if (isClosed) return;

    _tempSub = _geyser.temperatureStream.listen((temp) {
      if (isClosed) return;
      emit(state.copyWith(
        snapshot: state.snapshot.copyWith(temperature: temp),
      ));
    });

    _stateSub = _geyser.geyserStateStream.listen((isOn) {
      if (isClosed) return;
      emit(state.copyWith(
        snapshot: state.snapshot.copyWith(isOn: isOn),
        isBusy: false,
      ));
    });
  }

  Future<void> _stopStreams() async {
    await _tempSub?.cancel();
    _tempSub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    await _geyser.stopListening();
  }

  // ── Lifecycle ─────────────────────────────────────────────────────

  @override
  Future<void> close() async {
    await _bleSub?.cancel();
    await _stopStreams();
    await _stopRemoteSync();
    return super.close();
  }
}
