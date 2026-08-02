import 'package:flutter_test/flutter_test.dart';
import 'package:gs_rework/domain/geyser/entities/daily_stats.dart';
import 'package:gs_rework/domain/geyser/entities/geyser_config.dart';
import 'package:gs_rework/presentation/stats/device_stats_cubit.dart';

/// The savings model (Tier 1): what this product saves is the STANDING
/// LOSS avoided while the geyser is depowered. Water the household
/// actually draws must be heated either way and is not a saving.
void main() {
  DeviceStatsState stateWith({
    required double poweredHours,
    double elapsedHours = 24,
    int tank = 150,
    double standingLoss = 2.2,
  }) {
    return DeviceStatsState(
      stats: DailyStats(runtimeSeconds: (poweredHours * 3600).round()),
      config: GeyserConfig(tankSize: tank, elementKw: 3.0, costPerKwh: 2.79),
      standingLossKwhPerDay: standingLoss,
      elapsedHoursToday: elapsedHours,
    );
  }

  group('savings model', () {
    test('powered all day saves nothing', () {
      final s = stateWith(poweredHours: 24);
      expect(s.unpoweredHours, 0);
      expect(s.savedKwh, 0);
      expect(s.savedPercent, 0);
      expect(s.actualKwh, closeTo(9.0, 0.001)); // full baseline
    });

    test('never powered saves the whole standing loss', () {
      final s = stateWith(poweredHours: 0);
      expect(s.unpoweredHours, 24);
      expect(s.savedKwh, closeTo(2.2, 0.001));
      expect(s.savedPercent, closeTo(2.2 / 9.0 * 100, 0.01));
    });

    test('a realistic 6 h/day schedule lands in the published 10-20% band',
        () {
      final s = stateWith(poweredHours: 6);
      // 18 unpowered hours x (2.2/24) kWh/h = 1.65 kWh
      expect(s.savedKwh, closeTo(1.65, 0.001));
      expect(s.savedPercent, greaterThan(10));
      expect(s.savedPercent, lessThan(20));
    });

    test('REGRESSION: powered hours x element kW no longer zeroes savings',
        () {
      // The old model charged 3 kW for every powered hour, so 3 h/day
      // already exhausted a 9 kWh baseline and every user saw 0%.
      final s = stateWith(poweredHours: 6);
      expect(s.actualKwh, lessThan(9.0));
      expect(s.savedKwh, greaterThan(0));
    });

    test('savings are pro-rated for a partial day', () {
      // 09:00, geyser powered 1 h so far -> 8 unpowered hours.
      final s = stateWith(poweredHours: 1, elapsedHours: 9);
      expect(s.savedKwh, closeTo(2.2 / 24 * 8, 0.001));
      // Baseline is also pro-rated, so the percentage stays sane.
      expect(s.baselineKwh, closeTo(9.0 * 9 / 24, 0.001));
      expect(s.savedPercent, greaterThan(0));
      expect(s.savedPercent, lessThan(30));
    });

    test('saving can never exceed the baseline, and cost tracks kWh', () {
      final s = stateWith(poweredHours: 0, standingLoss: 999);
      expect(s.savedKwh, lessThanOrEqualTo(s.baselineKwh));
      expect(s.actualKwh, greaterThanOrEqualTo(0));
      expect(s.savedCost, closeTo(s.savedKwh * 2.79, 0.001));
    });

    test('runtime beyond elapsed time cannot produce negative unpowered',
        () {
      // Clock skew / stats arriving for a longer window than elapsed.
      final s = stateWith(poweredHours: 12, elapsedHours: 9);
      expect(s.unpoweredHours, 0);
      expect(s.savedKwh, 0);
    });

    test('tank size selects its own baseline', () {
      final small = stateWith(poweredHours: 0, tank: 100, standingLoss: 1.6);
      expect(small.baselineKwh, closeTo(5.0, 0.001));
      expect(small.savedKwh, closeTo(1.6, 0.001));
    });
  });
}
