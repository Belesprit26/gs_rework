import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../../domain/geyser/entities/daily_stats.dart';
import '../../../domain/geyser/entities/geyser_live.dart';
import '../../../domain/geyser/entities/geyser_settings.dart';
import '../../../domain/geyser/repositories/rtdb_repository.dart';

class FirebaseRtdbRepository implements RtdbRepository {
  FirebaseRtdbRepository({
    required FirebaseAuth auth,
    required FirebaseDatabase database,
  })  : _auth = auth,
        _db = database;

  final FirebaseAuth _auth;
  final FirebaseDatabase _db;

  DatabaseReference _userRef() {
    final uid = _auth.currentUser!.uid;
    return _db.ref('gs/$uid');
  }

  // ── Live telemetry ─────────────────────────────────────────────

  @override
  Stream<GeyserLive> watchLive(String deviceId) {
    return _userRef()
        .child('live/$deviceId')
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return const GeyserLive();
      return GeyserLive.fromMap(data);
    });
  }

  // ── Settings ───────────────────────────────────────────────────

  @override
  Stream<GeyserSettings> watchSettings(String deviceId) {
    return _userRef()
        .child('set/$deviceId')
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return const GeyserSettings();
      return GeyserSettings.fromMap(data);
    });
  }

  @override
  Future<GeyserSettings> readSettings(String deviceId) async {
    final snap = await _userRef().child('set/$deviceId').get();
    final data = snap.value as Map<dynamic, dynamic>?;
    if (data == null) return const GeyserSettings();
    return GeyserSettings.fromMap(data);
  }

  @override
  Future<void> writeSettings(
      String deviceId, Map<String, dynamic> fields) async {
    await _userRef().child('set/$deviceId').update(fields);
  }

  @override
  Future<bool> toggleRelay(
    String deviceId,
    bool desiredState, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    // 1. Write the desired state to the settings node.
    await _userRef().child('set/$deviceId').update({'on': desiredState});

    // 2. Wait for the live node to confirm within the timeout.
    final completer = Completer<bool>();
    late StreamSubscription<DatabaseEvent> sub;

    sub = _userRef().child('live/$deviceId/on').onValue.listen((event) {
      final actual = event.snapshot.value as bool?;
      if (actual == desiredState && !completer.isCompleted) {
        completer.complete(true);
      }
    });

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete(false);
    });

    final confirmed = await completer.future;
    timer.cancel();
    await sub.cancel();
    return confirmed;
  }

  // ── Stats ──────────────────────────────────────────────────────

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Stream<DailyStats> watchTodayStats(String deviceId) {
    final today = _dateKey(DateTime.now());
    return _userRef()
        .child('stats/$deviceId/$today')
        .onValue
        .map((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      return DailyStats.fromMap(data);
    });
  }

  // ── Meta ───────────────────────────────────────────────────────

  @override
  Future<void> touchAppActive() async {
    await _userRef().child('meta/app').set(ServerValue.timestamp);
  }

  @override
  Future<DateTime?> getLastBoot() async {
    final snap = await _userRef().child('meta/boot').get();
    if (!snap.exists || snap.value == null) return null;
    final epoch = (snap.value as num).toInt();
    return DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
  }
}
