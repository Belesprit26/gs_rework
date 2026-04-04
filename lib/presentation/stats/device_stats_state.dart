part of 'device_stats_cubit.dart';

/// Baseline kWh/day for an uncontrolled geyser by tank size (litres).
///
/// Sources: Eskom residential calculator, SANS 151, Savvy Plumbing,
/// PowerSaving.co.za. See STATS_IMPLEMENTATION.md for full citations.
const kBaselineKwhPerDay = <int, double>{
  100: 5.0,
  150: 9.0,
  200: 10.5,
};

class DeviceStatsState extends Equatable {
  const DeviceStatsState({
    this.stats = const DailyStats(),
    this.config = const GeyserConfig(),
    this.lastBoot,
  });

  final DailyStats stats;
  final GeyserConfig config;
  final DateTime? lastBoot;

  double get runtimeHours => stats.runtimeSeconds / 3600.0;
  double get actualKwh => runtimeHours * config.elementKw;
  double get actualCost => actualKwh * config.costPerKwh;

  double get baselineKwh => kBaselineKwhPerDay[config.tankSize] ?? 9.0;
  double get savedKwh => (baselineKwh - actualKwh).clamp(0, double.infinity);
  double get savedCost => savedKwh * config.costPerKwh;
  double get savedPercent =>
      baselineKwh > 0 ? (savedKwh / baselineKwh * 100) : 0;

  bool get hasData => stats.runtimeSeconds > 0 || stats.cycleCount > 0;

  DeviceStatsState copyWith({
    DailyStats? stats,
    GeyserConfig? config,
    Object? lastBoot = _sentinel,
  }) {
    return DeviceStatsState(
      stats: stats ?? this.stats,
      config: config ?? this.config,
      lastBoot: identical(lastBoot, _sentinel)
          ? this.lastBoot
          : lastBoot as DateTime?,
    );
  }

  @override
  List<Object?> get props => [stats, config, lastBoot];
}

const _sentinel = Object();
