import 'package:equatable/equatable.dart';

/// A BLE device discovered during a scan.
class ScannedDevice extends Equatable {
  const ScannedDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  /// Platform-specific identifier (remoteId on Android/iOS).
  final String id;

  /// Advertised device name (may be empty for unnamed devices).
  final String name;

  /// Signal strength in dBm (closer to 0 = stronger).
  final int rssi;

  @override
  List<Object?> get props => [id, name, rssi];

  @override
  String toString() => 'ScannedDevice($name, $id, ${rssi}dBm)';
}
