import 'package:equatable/equatable.dart';

/// Settings/command node in RTDB: `gs/{uid}/set/{did}`.
/// The app writes to this, and the ESP reads via SSE.
class GeyserSettings extends Equatable {
  const GeyserSettings({
    this.on = false,
    this.maxTemp = 60,
    this.minTemp = 30,
    this.autoReheat = false,
    this.timerMask = 0,
    this.customTimer = 0,
    this.maxOnMinutes = 240,
    this.currentSensor = false,
    this.leakSensor = false,
  });

  final bool on;
  final int maxTemp;
  final int minTemp;
  final bool autoReheat;

  /// Bitmask for preset timers (see `timer_presets.dart` for the schedule).
  final int timerMask;

  /// Custom timer in minutes since midnight (0 = disabled).
  final int customTimer;

  /// Max continuous relay-ON time in minutes (0 = disabled).
  final int maxOnMinutes;

  /// User-declared: this unit has a current (power) sensor. App-side
  /// config today; firmware ignores unknown keys until it grows a
  /// consumer (APP_FIRMWARE_CONTRACT.md).
  final bool currentSensor;

  /// User-declared: this unit has a leak-detection probe. Never used to
  /// suppress an arriving EVT_LEAK — if the event fires, water is real.
  final bool leakSensor;

  factory GeyserSettings.fromMap(Map<dynamic, dynamic> map) {
    return GeyserSettings(
      on: map['on'] as bool? ?? false,
      maxTemp: (map['max'] as num?)?.toInt() ?? 60,
      minTemp: (map['min'] as num?)?.toInt() ?? 30,
      autoReheat: map['ar'] as bool? ?? false,
      timerMask: (map['tmask'] as num?)?.toInt() ?? 0,
      customTimer: (map['tcust'] as num?)?.toInt() ?? 0,
      maxOnMinutes: (map['maxon'] as num?)?.toInt() ?? 240,
      currentSensor: map['cs'] as bool? ?? false,
      leakSensor: map['ls'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'on': on,
        'max': maxTemp,
        'min': minTemp,
        'ar': autoReheat,
        'tmask': timerMask,
        'tcust': customTimer,
        'maxon': maxOnMinutes,
        'cs': currentSensor,
        'ls': leakSensor,
      };

  GeyserSettings copyWith({
    bool? on,
    int? maxTemp,
    int? minTemp,
    bool? autoReheat,
    int? timerMask,
    int? customTimer,
    int? maxOnMinutes,
    bool? currentSensor,
    bool? leakSensor,
  }) {
    return GeyserSettings(
      on: on ?? this.on,
      maxTemp: maxTemp ?? this.maxTemp,
      minTemp: minTemp ?? this.minTemp,
      autoReheat: autoReheat ?? this.autoReheat,
      timerMask: timerMask ?? this.timerMask,
      customTimer: customTimer ?? this.customTimer,
      maxOnMinutes: maxOnMinutes ?? this.maxOnMinutes,
      currentSensor: currentSensor ?? this.currentSensor,
      leakSensor: leakSensor ?? this.leakSensor,
    );
  }

  @override
  List<Object?> get props => [
        on,
        maxTemp,
        minTemp,
        autoReheat,
        timerMask,
        customTimer,
        maxOnMinutes,
        currentSensor,
        leakSensor,
      ];
}
