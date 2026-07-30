import 'package:equatable/equatable.dart';

/// A point-in-time snapshot of all geyser sensor/state data.
///
/// This is the single domain model that the UI binds to.
/// It aggregates everything we can read from the ESP32's GATT service.
class GeyserSnapshot extends Equatable {
  const GeyserSnapshot({
    this.temperature = 0,
    this.isOn = false,
    this.minTemp = 30,
    this.maxTemp = 60,
    this.autoReheat = false,
    this.timers = const [],
    this.firmwareVersion,
    this.maxOnMinutes = 240,
  });

  /// Current water temperature in °C.  Negative means sensor offline.
  final double temperature;

  /// Whether the relay is closed, i.e. mains is supplied to the geyser.
  /// The element itself still cycles under the geyser's own thermostat
  /// inside this window.
  final bool isOn;

  /// Minimum allowed temperature setting (°C).
  final int minTemp;

  /// Maximum allowed temperature setting (°C).
  final int maxTemp;

  /// Whether the geyser auto-turns ON when temp drops to [minTemp].
  /// When disabled, the app should alert the user instead.
  final bool autoReheat;

  /// Active timer configurations (see `timer_presets.dart` for preset schedule).
  final List<GeyserTimer> timers;

  /// Firmware version string from the ESP32 (e.g. "0.2.0").
  final String? firmwareVersion;

  /// Max continuous relay-ON time in minutes (0 = disabled, default 240).
  final int maxOnMinutes;

  /// True when the firmware reports the temperature sensor is unresponsive.
  /// The sentinel value -1 is only pushed by the firmware itself after
  /// confirmed sensor failure with rediscovery attempts exhausted.
  bool get isSensorOffline => temperature < 0;

  GeyserSnapshot copyWith({
    double? temperature,
    bool? isOn,
    int? minTemp,
    int? maxTemp,
    bool? autoReheat,
    List<GeyserTimer>? timers,
    String? firmwareVersion,
    int? maxOnMinutes,
  }) {
    return GeyserSnapshot(
      temperature: temperature ?? this.temperature,
      isOn: isOn ?? this.isOn,
      minTemp: minTemp ?? this.minTemp,
      maxTemp: maxTemp ?? this.maxTemp,
      autoReheat: autoReheat ?? this.autoReheat,
      timers: timers ?? this.timers,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      maxOnMinutes: maxOnMinutes ?? this.maxOnMinutes,
    );
  }

  @override
  List<Object?> get props => [
        temperature,
        isOn,
        minTemp,
        maxTemp,
        autoReheat,
        timers,
        firmwareVersion,
        maxOnMinutes,
      ];
}

/// A single ON-only timer entry.
///
/// Timers are "wake-up alarms" — they turn the geyser ON at the
/// scheduled time.  temp_max (thermostat) is responsible for OFF.
///
/// BLE format: 4 bytes per timer [is_preset, enabled, hour, minute].
/// Indices 0–3 are preset off-peak timers (fixed times, enable only).
/// Index 4 is a fully custom timer (editable time + enable).
class GeyserTimer extends Equatable {
  const GeyserTimer({
    required this.hour,
    required this.minute,
    this.enabled = true,
    this.isPreset = false,
  });

  final int hour;
  final int minute;
  final bool enabled;

  /// If true, this is a preset off-peak timer whose time cannot be
  /// changed by the user — only enabled/disabled.
  final bool isPreset;

  String get timeFormatted =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  GeyserTimer copyWith({
    int? hour,
    int? minute,
    bool? enabled,
    bool? isPreset,
  }) {
    return GeyserTimer(
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      enabled: enabled ?? this.enabled,
      isPreset: isPreset ?? this.isPreset,
    );
  }

  @override
  List<Object?> get props => [hour, minute, enabled, isPreset];
}
