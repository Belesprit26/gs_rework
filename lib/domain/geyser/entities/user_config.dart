import 'package:equatable/equatable.dart';

/// User-level configuration stored in Firestore at `users/{uid}`.
///
/// These fields are account-scoped: same electricity rate and
/// household regardless of which device is selected.
class UserConfig extends Equatable {
  const UserConfig({
    this.costPerKwh = 2.79,
    this.householdSize = 2,
  });

  /// Electricity cost in Rands per kWh.
  final double costPerKwh;

  /// Number of people in the household (1–8).
  final int householdSize;

  factory UserConfig.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserConfig();
    return UserConfig(
      costPerKwh: (map['costPerKwh'] as num?)?.toDouble() ?? 2.79,
      householdSize: (map['householdSize'] as num?)?.toInt() ?? 2,
    );
  }

  Map<String, dynamic> toMap() => {
        'costPerKwh': costPerKwh,
        'householdSize': householdSize,
      };

  UserConfig copyWith({
    double? costPerKwh,
    int? householdSize,
  }) {
    return UserConfig(
      costPerKwh: costPerKwh ?? this.costPerKwh,
      householdSize: householdSize ?? this.householdSize,
    );
  }

  @override
  List<Object?> get props => [costPerKwh, householdSize];
}
