import 'package:equatable/equatable.dart';

/// Real-time telemetry from the ESP32, read from RTDB `gs/{uid}/live/{did}`.
class GeyserLive extends Equatable {
  const GeyserLive({
    this.temperature = 0,
    this.isOn = false,
    this.lastSeen,
  });

  final double temperature;
  final bool isOn;

  /// Server timestamp of the last ESP push (epoch ms).
  /// Null if the device has never pushed.
  final DateTime? lastSeen;

  factory GeyserLive.fromMap(Map<dynamic, dynamic> map) {
    return GeyserLive(
      temperature: (map['t'] as num?)?.toDouble() ?? 0,
      isOn: map['on'] as bool? ?? false,
      lastSeen: map['at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['at'] as int)
          : null,
    );
  }

  @override
  List<Object?> get props => [temperature, isOn, lastSeen];
}
