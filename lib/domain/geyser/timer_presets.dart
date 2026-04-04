import 'entities/geyser_snapshot.dart';

/// Off-peak preset timer schedule.
///
/// Must stay in sync with firmware `device_state.c`:
///   PRESET_TIMER_HOURS[]   = { 4,  6, 15, 17 }
///   PRESET_TIMER_MINUTES[] = { 0,  0,  0,  0 }
///
/// Firmware enforces these at boot via `device_state_enforce_presets()`.
/// The RTDB `tmask` bitmask encodes which of these are enabled (bit 0 = index 0).
/// Over BLE the device sends actual hour/minute bytes, so these constants
/// are only used for RTDB reconstruction and old-firmware fallback.
const kPresetTimers = [
  (hour: 4, minute: 0),
  (hour: 6, minute: 0),
  (hour: 15, minute: 0),
  (hour: 17, minute: 0),
];

const kCustomTimerDefault = (hour: 6, minute: 0);

/// Builds the default timer list (all disabled) for old-firmware fallback.
List<GeyserTimer> defaultTimers() {
  return [
    for (final p in kPresetTimers)
      GeyserTimer(hour: p.hour, minute: p.minute, isPreset: true, enabled: false),
    GeyserTimer(
      hour: kCustomTimerDefault.hour,
      minute: kCustomTimerDefault.minute,
      isPreset: false,
      enabled: false,
    ),
  ];
}
