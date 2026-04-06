import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/local/prefs_manager.dart';

part 'device_registry_state.dart';

/// Manages the list of known devices and which one is selected.
///
/// Populated from [PrefsManager] on startup.  New devices are added
/// after provisioning.  The selected device drives which RTDB paths
/// [GeyserControlCubit] and [DeviceStatsCubit] subscribe to.
class DeviceRegistryCubit extends Cubit<DeviceRegistryState> {
  DeviceRegistryCubit({required PrefsManager prefsManager})
      : _prefs = prefsManager,
        super(const DeviceRegistryState()) {
    load();
  }

  final PrefsManager _prefs;

  /// Load all known devices from SharedPreferences.
  void load() {
    if (isClosed) return;
    final mappings = _prefs.getAllDeviceMappings();
    if (mappings.isEmpty) return;

    final devices = mappings.entries.map((e) {
      final rtdbId = e.value;
      return DeviceInfo(
        rtdbDeviceId: rtdbId,
        bleMac: e.key,
        nickname: _prefs.getDeviceNickname(rtdbId) ?? 'My Geyser',
      );
    }).toList();

    emit(state.copyWith(devices: devices, selectedIndex: 0));
  }

  /// Add a newly provisioned device to the registry.
  void addDevice(DeviceInfo device) {
    if (isClosed) return;
    final existing = state.devices.indexWhere(
      (d) => d.rtdbDeviceId == device.rtdbDeviceId,
    );

    if (existing >= 0) {
      final updated = List<DeviceInfo>.of(state.devices);
      updated[existing] = device;
      emit(state.copyWith(devices: updated, selectedIndex: existing));
    } else {
      final updated = [...state.devices, device];
      emit(state.copyWith(
        devices: updated,
        selectedIndex: updated.length - 1,
      ));
    }
  }

  /// Change the selected device (e.g. from PageView swipe).
  void selectDevice(int index) {
    if (isClosed) return;
    if (index < 0 || index >= state.devices.length) return;
    if (index == state.selectedIndex) return;
    emit(state.copyWith(selectedIndex: index));
  }

  /// Update the nickname for a device (e.g. after BLE read or rename).
  void updateNickname(String rtdbDeviceId, String nickname) {
    if (isClosed) return;
    final idx = state.devices.indexWhere(
      (d) => d.rtdbDeviceId == rtdbDeviceId,
    );
    if (idx < 0) return;

    final updated = List<DeviceInfo>.of(state.devices);
    updated[idx] = DeviceInfo(
      rtdbDeviceId: rtdbDeviceId,
      bleMac: updated[idx].bleMac,
      nickname: nickname,
    );
    emit(state.copyWith(devices: updated));
  }

  /// Remove a device from the registry and clean up its prefs data.
  Future<void> removeDevice(String rtdbDeviceId) async {
    if (isClosed) return;
    final idx = state.devices.indexWhere(
      (d) => d.rtdbDeviceId == rtdbDeviceId,
    );
    if (idx < 0) return;

    final device = state.devices[idx];
    await _prefs.removeDevice(device.bleMac, device.rtdbDeviceId);

    final updated = List<DeviceInfo>.of(state.devices)..removeAt(idx);
    final newIndex = updated.isEmpty
        ? 0
        : state.selectedIndex >= updated.length
            ? updated.length - 1
            : state.selectedIndex;
    emit(state.copyWith(devices: updated, selectedIndex: newIndex));
  }

  /// Reset the registry on sign-out.
  void clear() {
    if (isClosed) return;
    emit(const DeviceRegistryState());
  }
}
