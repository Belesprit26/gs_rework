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
  });

  final bool on;
  final int maxTemp;
  final int minTemp;
  final bool autoReheat;

  /// Bitmask for preset timers: bit0=04:00, bit1=06:00, bit2=15:00, bit3=17:00.
  final int timerMask;

  /// Custom timer in minutes since midnight (0 = disabled).
  final int customTimer;

  factory GeyserSettings.fromMap(Map<dynamic, dynamic> map) {
    return GeyserSettings(
      on: map['on'] as bool? ?? false,
      maxTemp: (map['max'] as num?)?.toInt() ?? 60,
      minTemp: (map['min'] as num?)?.toInt() ?? 30,
      autoReheat: map['ar'] as bool? ?? false,
      timerMask: (map['tmask'] as num?)?.toInt() ?? 0,
      customTimer: (map['tcust'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'on': on,
        'max': maxTemp,
        'min': minTemp,
        'ar': autoReheat,
        'tmask': timerMask,
        'tcust': customTimer,
      };

  GeyserSettings copyWith({
    bool? on,
    int? maxTemp,
    int? minTemp,
    bool? autoReheat,
    int? timerMask,
    int? customTimer,
  }) {
    return GeyserSettings(
      on: on ?? this.on,
      maxTemp: maxTemp ?? this.maxTemp,
      minTemp: minTemp ?? this.minTemp,
      autoReheat: autoReheat ?? this.autoReheat,
      timerMask: timerMask ?? this.timerMask,
      customTimer: customTimer ?? this.customTimer,
    );
  }

  @override
  List<Object?> get props =>
      [on, maxTemp, minTemp, autoReheat, timerMask, customTimer];
}
