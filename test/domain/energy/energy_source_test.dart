import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/domain/energy/energy_source.dart';
import 'package:gs_rework/presentation/stats/device_stats_cubit.dart';

/// Locks the E2 energy seam: the estimated source carries the Tier-1
/// standing-loss formulas VERBATIM (behaviour identical to the old
/// DeviceStatsState getters), and the measured source is an honest
/// delegate until the current-sense firmware ships.
void main() {
  const day = (
    standingLossKwhPerDay: 2.4, // 0.1 kWh/h
    unpoweredHours: 10.0,
    baselineKwh: 6.0,
  );

  group('EstimatedEnergySource', () {
    const est = EstimatedEnergySource();

    test('savedKwh = standing loss/hour × unpowered hours', () {
      expect(est.savedKwh(day), closeTo(1.0, 1e-9));
    });

    test('savedKwh clamps at baseline', () {
      const extreme = (
        standingLossKwhPerDay: 24.0, // 1 kWh/h
        unpoweredHours: 20.0,
        baselineKwh: 6.0,
      );
      expect(est.savedKwh(extreme), 6.0);
      expect(est.actualKwh(extreme), 0.0);
    });

    test('actualKwh = baseline − saved, floored at 0', () {
      expect(est.actualKwh(day), closeTo(5.0, 1e-9));
    });
  });

  group('selection + measured socket', () {
    test('select() maps the declared hardware', () {
      expect(EnergySource.select(measuredHardware: false),
          isA<EstimatedEnergySource>());
      expect(EnergySource.select(measuredHardware: true),
          isA<MeasuredEnergySource>());
    });

    test('measured delegates to the estimate until firmware exists', () {
      const measured = MeasuredEnergySource();
      const est = EstimatedEnergySource();
      expect(measured.savedKwh(day), est.savedKwh(day));
      expect(measured.actualKwh(day), est.actualKwh(day));
      expect(measured.isMeasured, isTrue);
      expect(est.isMeasured, isFalse);
    });
  });

  group('DeviceStatsState parity (behaviour lock)', () {
    test('state getters produce the pre-seam numbers', () {
      // 6 h powered of a 24 h day → 18 h unpowered; 150 L baseline 9.0.
      const state = DeviceStatsState(
        standingLossKwhPerDay: 2.2,
        elapsedHoursToday: 24,
      );
      // No runtime recorded → unpowered = 24 h; saved = 2.2 clamped
      // within baseline 9.0.
      expect(state.savedKwh, closeTo(2.2, 1e-9));
      expect(state.actualKwh, closeTo(6.8, 1e-9));
      // Flag flips the source but (today) not the numbers.
      final withSensor = state.copyWith(hasCurrentSensor: true);
      expect(withSensor.energySource.isMeasured, isTrue);
      expect(withSensor.savedKwh, state.savedKwh);
    });
  });
}
