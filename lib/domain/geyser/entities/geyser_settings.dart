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

  factory GeyserSettings.fromMap(Map<dynamic, dynamic> map) {
    return GeyserSettings(
      on: map['on'] as bool? ?? false,
      maxTemp: (map['max'] as num?)?.toInt() ?? 60,
      minTemp: (map['min'] as num?)?.toInt() ?? 30,
      autoReheat: map['ar'] as bool? ?? false,
      timerMask: (map['tmask'] as num?)?.toInt() ?? 0,
      customTimer: (map['tcust'] as num?)?.toInt() ?? 0,
      maxOnMinutes: (map['maxon'] as num?)?.toInt() ?? 240,
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
      };

  GeyserSettings copyWith({
    bool? on,
    int? maxTemp,
    int? minTemp,
    bool? autoReheat,
    int? timerMask,
    int? customTimer,
    int? maxOnMinutes,
  }) {
    return GeyserSettings(
      on: on ?? this.on,
      maxTemp: maxTemp ?? this.maxTemp,
      minTemp: minTemp ?? this.minTemp,
      autoReheat: autoReheat ?? this.autoReheat,
      timerMask: timerMask ?? this.timerMask,
      customTimer: customTimer ?? this.customTimer,
      maxOnMinutes: maxOnMinutes ?? this.maxOnMinutes,
    );
  }

  @override
  List<Object?> get props =>
      [on, maxTemp, minTemp, autoReheat, timerMask, customTimer, maxOnMinutes];
}
