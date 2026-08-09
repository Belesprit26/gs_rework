import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/domain/geyser/temp_limits.dart';

/// Mirrors the firmware's device_state_clamp_limits() — these cases
/// must stay in lockstep with device_state.c.
void main() {
  group('clampTempLimits', () {
    test('passes through values already in range with enough gap', () {
      expect(clampTempLimits(min: 30, max: 60), (min: 30, max: 60));
    });

    test('clamps min below floor', () {
      expect(clampTempLimits(min: 0, max: 60), (min: 5, max: 60));
    });

    test('clamps min above ceiling', () {
      expect(clampTempLimits(min: 55, max: 60), (min: 50, max: 60));
    });

    test('clamps max below floor', () {
      expect(clampTempLimits(min: 20, max: 40), (min: 20, max: 51));
    });

    test('clamps max above ceiling', () {
      expect(clampTempLimits(min: 30, max: 80), (min: 30, max: 70));
    });

    test('enforces deadband by raising max (the chatter case)', () {
      // min=50/max=51 was the relay-chatter configuration.
      expect(clampTempLimits(min: 50, max: 51), (min: 50, max: 55));
    });

    test('deadband respects max ceiling', () {
      // min at its ceiling: max rises to min+5=55, well under 70.
      expect(clampTempLimits(min: 50, max: 52), (min: 50, max: 55));
    });

    test('extreme garbage input still yields a valid pair', () {
      final r = clampTempLimits(min: 255, max: 0);
      expect(r.min, inInclusiveRange(tempMinFloor, tempMinCeil));
      expect(r.max, inInclusiveRange(tempMaxFloor, tempMaxCeil));
      expect(r.max - r.min, greaterThanOrEqualTo(tempMinDeadband));
    });
  });
}
