import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/firebase/config/geyser_config_repository.dart';
import '../../domain/geyser/entities/daily_stats.dart';
import '../../domain/geyser/entities/geyser_config.dart';
import '../../domain/geyser/repositories/rtdb_repository.dart';

part 'device_stats_state.dart';

class DeviceStatsCubit extends Cubit<DeviceStatsState> {
  DeviceStatsCubit({
    required RtdbRepository rtdbRepository,
    required GeyserConfigRepository configRepository,
    required FirebaseAuth firebaseAuth,
    required String deviceId,
  })  : _rtdb = rtdbRepository,
        _config = configRepository,
        _deviceId = deviceId,
        super(const DeviceStatsState()) {
    _authSub = firebaseAuth.authStateChanges().listen(_onAuthChanged);
  }

  final RtdbRepository _rtdb;
  final GeyserConfigRepository _config;
  String _deviceId;

  StreamSubscription<User?>? _authSub;
  StreamSubscription<DailyStats>? _statsSub;
  StreamSubscription<GeyserConfig>? _configSub;
  String _currentDate = '';
  bool _activated = false;

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
    _startConfigStream();

    try {
      final boot = await _rtdb.getLastBoot(_deviceId);
      if (isClosed) return;
      emit(state.copyWith(lastBoot: boot));
    } catch (_) {}

    _startStatsStream();
  }

  void _startConfigStream() {
    _configSub?.cancel();
    _configSub = _config.watchConfig(_deviceId).listen((config) {
      if (isClosed) return;
      emit(state.copyWith(config: config));
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
      emit(state.copyWith(stats: stats));
    });
  }

  /// Switch to a different device's stats (multi-device swipe).
  void switchDevice(String deviceId) async {
    if (isClosed) return;
    _deviceId = deviceId;
    emit(state.copyWith(stats: const DailyStats(), lastBoot: null));

    _startConfigStream();
    _startStatsStream();

    try {
      final boot = await _rtdb.getLastBoot(_deviceId);
      if (isClosed) return;
      emit(state.copyWith(lastBoot: boot));
    } catch (_) {}
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Future<void> close() async {
    await _authSub?.cancel();
    await _statsSub?.cancel();
    await _configSub?.cancel();
    return super.close();
  }
}
