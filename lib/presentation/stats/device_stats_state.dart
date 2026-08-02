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
    this.standingLossKwhPerDay = 2.2,
    this.elapsedHoursToday = 24,
  });

  final DailyStats stats;
  final GeyserConfig config;
  final DateTime? lastBoot;

  /// Standing heat loss of this tank, kWh per 24 h (Remote Config).
  final double standingLossKwhPerDay;

  /// Hours of the current day elapsed so far. Stats accumulate through
  /// the day, so every figure below is pro-rated by this — otherwise a
  /// reading at 09:00 would claim a whole day's saving.
  final double elapsedHoursToday;

  /// Hours the geyser was supplied with mains today.
  double get poweredHours => stats.runtimeSeconds / 3600.0;

  /// Hours it sat unpowered today — where the saving comes from.
  double get unpoweredHours =>
      (elapsedHoursToday - poweredHours).clamp(0, 24).toDouble();

  // ── Energy model ──────────────────────────────────────────────────
  //
  // What this product saves is the STANDING LOSS avoided while the
  // geyser is depowered: the energy an always-on tank burns just
  // holding temperature. The hot water the household actually draws
  // has to be heated either way, so it is not a saving and must not be
  // counted as one.
  //
  //   savedKwh  = standingLoss/hour × hours unpowered
  //   actualKwh = baseline for the elapsed period − savedKwh
  //
  // Deliberately NOT `poweredHours × elementKw`: relay-ON is not
  // element-ON. Inside a powered window the geyser's own thermostat
  // cycles the element at a low duty once up to temperature, so that
  // form overstated consumption by ~8x for an always-on unit and
  // clamped the displayed saving to zero for most users.
  //
  // Caps out near 25% of baseline, consistent with published figures
  // for geyser timers (typically 10–15%). Treat as an estimate: it is
  // derived from measured runtime and a per-tank standing-loss
  // constant, not from metered consumption.

  double get standingLossKwhPerHour => standingLossKwhPerDay / 24.0;

  /// Baseline consumption for the portion of the day elapsed so far.
  double get baselineKwh =>
      (kBaselineKwhPerDay[config.tankSize] ?? 9.0) *
      (elapsedHoursToday / 24.0);

  double get savedKwh =>
      (standingLossKwhPerHour * unpoweredHours).clamp(0, baselineKwh);

  double get actualKwh => (baselineKwh - savedKwh).clamp(0, double.infinity);

  double get actualCost => actualKwh * config.costPerKwh;
  double get savedCost => savedKwh * config.costPerKwh;
  double get savedPercent =>
      baselineKwh > 0 ? (savedKwh / baselineKwh * 100) : 0;

  bool get hasData => stats.runtimeSeconds > 0 || stats.cycleCount > 0;

  DeviceStatsState copyWith({
    DailyStats? stats,
    GeyserConfig? config,
    Object? lastBoot = _sentinel,
    double? standingLossKwhPerDay,
    double? elapsedHoursToday,
  }) {
    return DeviceStatsState(
      stats: stats ?? this.stats,
      config: config ?? this.config,
      lastBoot: identical(lastBoot, _sentinel)
          ? this.lastBoot
          : lastBoot as DateTime?,
      standingLossKwhPerDay:
          standingLossKwhPerDay ?? this.standingLossKwhPerDay,
      elapsedHoursToday: elapsedHoursToday ?? this.elapsedHoursToday,
    );
  }

  @override
  List<Object?> get props =>
      [stats, config, lastBoot, standingLossKwhPerDay, elapsedHoursToday];
}

const _sentinel = Object();
