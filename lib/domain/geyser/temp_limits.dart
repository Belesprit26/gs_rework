/// Temperature-limit bounds and clamping, mirroring the firmware's
/// `device_state_clamp_limits()` (device_state.c/h) exactly.
///
/// The firmware is authoritative — it re-clamps every value it receives
/// over BLE or RTDB. Mirroring the same rule here means the UI never
/// briefly shows a value the device is about to override.
library;

const int tempMinFloor = 5;
const int tempMinCeil = 50;
const int tempMaxFloor = 51;
const int tempMaxCeil = 65;

/// Minimum gap (°C) enforced between min and max. Prevents rapid
/// ON/OFF relay cycling when auto-reheat is enabled and the two limits
/// are set almost equal (e.g. min=50, max=51).
const int tempMinDeadband = 5;

/// Clamp a (min, max) pair to the ranges above and enforce
/// [tempMinDeadband] between them. Same order of operations as the
/// firmware: prefer raising max; if max is already at its ceiling,
/// lower min instead.
({int min, int max}) clampTempLimits({required int min, required int max}) {
  var mn = min.clamp(tempMinFloor, tempMinCeil);
  var mx = max.clamp(tempMaxFloor, tempMaxCeil);

  if (mx < mn + tempMinDeadband) {
    mx = mn + tempMinDeadband;
    if (mx > tempMaxCeil) {
      mx = tempMaxCeil;
      if (mn > mx - tempMinDeadband) mn = mx - tempMinDeadband;
    }
  }

  return (min: mn, max: mx);
}
