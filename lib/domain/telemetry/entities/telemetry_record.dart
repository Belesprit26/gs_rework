import 'package:equatable/equatable.dart';

/// A single telemetry reading captured from the ESP32 via BLE.
///
/// Recorded periodically (e.g. every 30s) while connected and stored
/// locally for up to 7 days before being synced to Firebase.
class TelemetryRecord extends Equatable {
  const TelemetryRecord({
    this.id,
    required this.deviceId,
    required this.timestamp,
    required this.temperature,
    required this.isOn,
    required this.minTemp,
    required this.maxTemp,
    this.synced = false,
  });

  /// Auto-increment primary key (null for new records).
  final int? id;

  /// BLE device ID this reading came from.
  final String deviceId;

  /// When the reading was taken (UTC).
  final DateTime timestamp;

  /// Water temperature in °C.
  final double temperature;

  /// Whether the relay was closed (mains supplied to the geyser).
  final bool isOn;

  /// Min temp limit at the time of reading.
  final int minTemp;

  /// Max temp limit at the time of reading.
  final int maxTemp;

  /// Whether this record has been pushed to Firebase.
  final bool synced;

  @override
  List<Object?> get props => [
        id,
        deviceId,
        timestamp,
        temperature,
        isOn,
        minTemp,
        maxTemp,
        synced,
      ];
}
