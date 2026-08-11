/// The energy-calculation seam (UX polish E2).
///
/// Every kWh figure the app shows flows through ONE of these, selected by
/// whether the user declared a current sensor on the unit (Sensors card,
/// `PrefsManager.hasCurrentSensor`). Today both implementations produce
/// the same numbers — the Tier-1 standing-loss estimate that shipped with
/// the savings card — because the current-sense firmware doesn't exist
/// yet. When it lands, [MeasuredEnergySource] swaps its internals for
/// metered kWh and nothing upstream changes.
///
/// The inputs mirror `DeviceStatsState`'s day context exactly; the
/// formulas here were MOVED from that state's getters, not rewritten —
/// see the model rationale comment there (standing loss avoided, not
/// runtime × element kW).
library;

/// Day-so-far context for the energy model.
typedef EnergyDayContext = ({
  /// Standing loss for this tank size, kWh per 24 h.
  double standingLossKwhPerDay,

  /// Hours the geyser sat unpowered so far today.
  double unpoweredHours,

  /// Baseline consumption for the elapsed portion of the day.
  double baselineKwh,
});

abstract interface class EnergySource {
  /// Whether figures come from metered hardware rather than the model.
  bool get isMeasured;

  /// kWh avoided so far today.
  double savedKwh(EnergyDayContext day);

  /// kWh actually consumed so far today.
  double actualKwh(EnergyDayContext day);

  /// Select the source for a device's declared hardware.
  static EnergySource select({required bool measuredHardware}) =>
      measuredHardware
          ? const MeasuredEnergySource()
          : const EstimatedEnergySource();
}

/// Tier-1 standing-loss model — the formulas from DeviceStatsState,
/// verbatim.
class EstimatedEnergySource implements EnergySource {
  const EstimatedEnergySource();

  @override
  bool get isMeasured => false;

  @override
  double savedKwh(EnergyDayContext day) =>
      (day.standingLossKwhPerDay / 24.0 * day.unpoweredHours)
          .clamp(0, day.baselineKwh);

  @override
  double actualKwh(EnergyDayContext day) =>
      (day.baselineKwh - savedKwh(day)).clamp(0, double.infinity);
}

/// The socket for the current-sense firmware.
///
/// The user has declared measuring hardware, but no measured feed exists
/// yet (firmware staged, not shipped — OUTSTANDING.md §4). Until it does,
/// this DELEGATES to the estimate so the numbers stay honest, while
/// [isMeasured] lets future UI label the difference the day real data
/// arrives.
class MeasuredEnergySource implements EnergySource {
  const MeasuredEnergySource();

  static const _fallback = EstimatedEnergySource();

  @override
  bool get isMeasured => true;

  @override
  double savedKwh(EnergyDayContext day) => _fallback.savedKwh(day);

  @override
  double actualKwh(EnergyDayContext day) => _fallback.actualKwh(day);
}
