import 'package:equatable/equatable.dart';

/// Per-device configuration stored in Firestore at
/// `users/{uid}/geyser_config/{deviceId}`.
///
/// These fields are hardware-specific: each physical geyser has its
/// own tank size and element wattage.
class DeviceConfig extends Equatable {
  const DeviceConfig({
    this.tankSize = 150,
    this.elementKw = 3.0,
  });

  /// Tank capacity in litres (100, 150, 200).
  final int tankSize;

  /// Heating element wattage in kW (2.0, 2.5, 3.0, 4.0).
  final double elementKw;

  factory DeviceConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const DeviceConfig();
    return DeviceConfig(
      tankSize: (map['tankSize'] as num?)?.toInt() ?? 150,
      elementKw: (map['elementKw'] as num?)?.toDouble() ?? 3.0,
    );
  }

  Map<String, dynamic> toMap() => {
        'tankSize': tankSize,
        'elementKw': elementKw,
      };

  DeviceConfig copyWith({
    int? tankSize,
    double? elementKw,
  }) {
    return DeviceConfig(
      tankSize: tankSize ?? this.tankSize,
      elementKw: elementKw ?? this.elementKw,
    );
  }

  @override
  List<Object?> get props => [tankSize, elementKw];
}
