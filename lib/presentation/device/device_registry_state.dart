part of 'device_registry_cubit.dart';

class DeviceInfo extends Equatable {
  const DeviceInfo({
    required this.rtdbDeviceId,
    required this.bleMac,
    required this.nickname,
  });

  final String rtdbDeviceId;
  final String bleMac;
  final String nickname;

  @override
  List<Object?> get props => [rtdbDeviceId, bleMac, nickname];
}

class DeviceRegistryState extends Equatable {
  const DeviceRegistryState({
    this.devices = const [],
    this.selectedIndex = 0,
  });

  final List<DeviceInfo> devices;
  final int selectedIndex;

  DeviceInfo? get selectedDevice =>
      devices.isNotEmpty && selectedIndex < devices.length
          ? devices[selectedIndex]
          : null;

  String? get selectedRtdbId => selectedDevice?.rtdbDeviceId;

  bool get isMultiDevice => devices.length > 1;

  DeviceRegistryState copyWith({
    List<DeviceInfo>? devices,
    int? selectedIndex,
  }) {
    return DeviceRegistryState(
      devices: devices ?? this.devices,
      selectedIndex: selectedIndex ?? this.selectedIndex,
    );
  }

  @override
  List<Object?> get props => [devices, selectedIndex];
}
