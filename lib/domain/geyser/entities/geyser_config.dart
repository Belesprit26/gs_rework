import 'package:equatable/equatable.dart';

import 'device_config.dart';
import 'user_config.dart';

/// Combined geyser configuration used by stats calculations and UI.
///
/// Composed from [DeviceConfig] (per-device, Firestore subcollection)
/// and [UserConfig] (user-scoped, Firestore user doc).
class GeyserConfig extends Equatable {
  const GeyserConfig({
    this.tankSize = 150,
    this.elementKw = 3.0,
    this.costPerKwh = 2.79,
    this.householdSize = 2,
  });

  /// Tank capacity in litres (100, 150, 200).
  final int tankSize;

  /// Heating element wattage in kW (2.0, 2.5, 3.0, 4.0).
  final double elementKw;

  /// Electricity cost in Rands per kWh.
  final double costPerKwh;

  /// Number of people in the household (1–8).
  final int householdSize;

  /// Construct from split config sources.
  factory GeyserConfig.fromParts({
    required DeviceConfig device,
    required UserConfig user,
  }) {
    return GeyserConfig(
      tankSize: device.tankSize,
      elementKw: device.elementKw,
      costPerKwh: user.costPerKwh,
      householdSize: user.householdSize,
    );
  }

  /// Legacy: parse from a single Firestore document (migration path).
  factory GeyserConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const GeyserConfig();
    return GeyserConfig(
      tankSize: (map['tankSize'] as num?)?.toInt() ?? 150,
      elementKw: (map['elementKw'] as num?)?.toDouble() ?? 3.0,
      costPerKwh: (map['costPerKwh'] as num?)?.toDouble() ?? 2.79,
      householdSize: (map['householdSize'] as num?)?.toInt() ?? 2,
    );
  }

  Map<String, dynamic> toMap() => {
        'tankSize': tankSize,
        'elementKw': elementKw,
        'costPerKwh': costPerKwh,
        'householdSize': householdSize,
      };

  DeviceConfig get deviceConfig => DeviceConfig(
        tankSize: tankSize,
        elementKw: elementKw,
      );

  UserConfig get userConfig => UserConfig(
        costPerKwh: costPerKwh,
        householdSize: householdSize,
      );

  GeyserConfig copyWith({
    int? tankSize,
    double? elementKw,
    double? costPerKwh,
    int? householdSize,
  }) {
    return GeyserConfig(
      tankSize: tankSize ?? this.tankSize,
      elementKw: elementKw ?? this.elementKw,
      costPerKwh: costPerKwh ?? this.costPerKwh,
      householdSize: householdSize ?? this.householdSize,
    );
  }

  @override
  List<Object?> get props => [tankSize, elementKw, costPerKwh, householdSize];
}
