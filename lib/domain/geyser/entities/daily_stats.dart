import 'package:equatable/equatable.dart';

/// Pre-aggregated daily stats from RTDB: `gs/{uid}/stats/{did}/{date}`.
class DailyStats extends Equatable {
  const DailyStats({
    this.runtimeSeconds = 0,
    this.cycleCount = 0,
  });

  final int runtimeSeconds;
  final int cycleCount;

  factory DailyStats.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const DailyStats();
    return DailyStats(
      runtimeSeconds: (map['rt'] as num?)?.toInt() ?? 0,
      cycleCount: (map['cy'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [runtimeSeconds, cycleCount];
}
