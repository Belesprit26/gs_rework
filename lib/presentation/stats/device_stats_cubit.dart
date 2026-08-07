import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/firebase/config/geyser_config_repository.dart';
import '../../domain/geyser/entities/daily_stats.dart';
import '../../domain/geyser/entities/geyser_config.dart';
import '../../domain/geyser/repositories/rtdb_repository.dart';
import '../device/device_selection_coordinator.dart';
import '../../domain/remote_config/repositories/remote_config_repository.dart';

part 'device_stats_state.dart';

class DeviceStatsCubit extends Cubit<DeviceStatsState>
    implements DeviceScoped {
  DeviceStatsCubit({
    required RtdbRepository rtdbRepository,
    required GeyserConfigRepository configRepository,
    required RemoteConfigRepository remoteConfigRepository,
    required FirebaseAuth firebaseAuth,
    required String deviceId,
  })  : _rtdb = rtdbRepository,
        _config = configRepository,
        _remoteConfig = remoteConfigRepository,
        _deviceId = deviceId,
        super(const DeviceStatsState()) {
    _authSub = firebaseAuth.authStateChanges().listen(_onAuthChanged);
  }

  final RtdbRepository _rtdb;
  final GeyserConfigRepository _config;
  final RemoteConfigRepository _remoteConfig;
  String _deviceId;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DailyStats>? _statsSub;
  StreamSubscription<GeyserConfig>? _configSub;
  Timer? _elapsedTimer;
  String _currentDate = '';
  bool _activated = false;

  /// Bumped on every (re)point so an in-flight getLastBoot from a
  /// superseded device can't emit its result over the current one.
  int _selectionGen = 0;

  /// Fraction of today elapsed so far — the savings maths is pro-rated
  /// by it, so it is refreshed periodically and whenever stats arrive.
  static double _elapsedHoursToday() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final hours = now.difference(startOfDay).inSeconds / 3600.0;
    // Never zero: a reading at 00:00:30 would otherwise divide the
    // baseline to nothing and show a wild percentage.
    return hours.clamp(0.05, 24.0).toDouble();
  }

  void _onAuthChanged(User? user) {
    if (isClosed) return;
    if (user != null && !_activated) {
      _activated = true;
      _activate();
    } else if (user == null) {
      _activated = false;
      _statsSub?.cancel();
      _configSub?.cancel();
      emit(const DeviceStatsState());
    }
  }

  Future<void> _activate() async {
    final gen = ++_selectionGen;
    _startConfigStream();
    _startElapsedTimer();
    emit(state.copyWith(elapsedHoursToday: _elapsedHoursToday()));
    _startStatsStream();
    await _loadLastBoot(gen);
  }

  /// Load the device's last-boot time, discarding the result if the
  /// selection changed while the request was in flight.
  Future<void> _loadLastBoot(int gen) async {
    try {
      final boot = await _rtdb.getLastBoot(_deviceId);
      if (isClosed || gen != _selectionGen) return;
      emit(state.copyWith(lastBoot: boot));
    } catch (_) {}
  }

  void _startConfigStream() {
    _configSub?.cancel();
    _configSub = _config.watchConfig(_deviceId).listen((config) {
      if (isClosed) return;
      emit(state.copyWith(
        config: config,
        // Standing loss is per tank size, so it must follow the config.
        standingLossKwhPerDay:
            _remoteConfig.standingLossKwhPerDay(config.tankSize),
      ));
    });
  }

  /// Keep the elapsed-day fraction current so the savings figure grows
  /// through the day even when no new stats arrive.
  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (isClosed) return;
      emit(state.copyWith(elapsedHoursToday: _elapsedHoursToday()));
    });
  }

  void _startStatsStream() {
    _statsSub?.cancel();
    _currentDate = _today();
    _statsSub = _rtdb.watchTodayStats(_deviceId).listen((stats) {
      if (isClosed) return;
      if (_today() != _currentDate) {
        _startStatsStream();
        return;
      }
      emit(state.copyWith(
        stats: stats,
        elapsedHoursToday: _elapsedHoursToday(),
      ));
    });
  }

  /// Point at a different device's stats.
  @override
  void switchDevice(String deviceId) {
    if (isClosed || _deviceId == deviceId) return;
    _deviceId = deviceId;

    // The config + stats streams require an authenticated user —
    // watchConfig throws synchronously otherwise, and that throw in a
    // fire-and-forget call surfaces as a FATAL unhandled error. Before
    // auth restores (the coordinator fans out at cold start, pre-auth),
    // just record the id; _activate() starts the streams once signed in.
    if (!_activated) return;

    final gen = ++_selectionGen;
    emit(state.copyWith(stats: const DailyStats(), lastBoot: null));
    _startConfigStream();
    _startStatsStream();
    _loadLastBoot(gen);
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<void> close() async {
    _elapsedTimer?.cancel();
    await _authSub?.cancel();
    await _statsSub?.cancel();
    await _configSub?.cancel();
    return super.close();
  }
}
