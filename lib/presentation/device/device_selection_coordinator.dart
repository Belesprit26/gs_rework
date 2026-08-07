import 'dart:async';

import 'device_registry_cubit.dart';

/// A screen/cubit whose data is scoped to one device and must re-point
/// when the selected device changes. Implemented by GeyserControlCubit
/// and DeviceStatsCubit. Kept as a narrow interface so the coordinator
/// doesn't depend on the cubits' repositories — and can be tested with
/// fakes.
abstract interface class DeviceScoped {
  void switchDevice(String deviceId);
}

/// Single point that fans a device selection out to everything scoped
/// to it.
///
/// [DeviceRegistryCubit] is the one writer of "which device is
/// selected". Anything that changes it — the dashboard swipe, the
/// Settings switcher, removing a device — just calls
/// `registry.selectDevice(...)`; this coordinator watches the registry
/// and re-points [GeyserControlCubit] and [DeviceStatsCubit] whenever
/// the selected device id actually changes.
///
/// Before this existed the fan-out was hand-wired into the dashboard's
/// page-change handler, so any *other* caller silently left the two
/// cubits pointing at the old device. Keeping the cubits ignorant of
/// each other (they don't listen to the registry themselves) means one
/// place to read when a desync is suspected.
class DeviceSelectionCoordinator {
  DeviceSelectionCoordinator({
    required DeviceRegistryCubit registry,
    required DeviceScoped geyserControl,
    required DeviceScoped stats,
  })  : _registry = registry,
        _geyserControl = geyserControl,
        _stats = stats;

  final DeviceRegistryCubit _registry;
  final DeviceScoped _geyserControl;
  final DeviceScoped _stats;

  StreamSubscription<DeviceRegistryState>? _sub;
  String? _lastDeviceId;

  /// Apply the current selection, then follow every change. Idempotent.
  void start() {
    if (_sub != null) return;
    _apply(_registry.state.selectedRtdbId);
    _sub = _registry.stream.listen((s) => _apply(s.selectedRtdbId));
  }

  void _apply(String? deviceId) {
    // A null selection means the registry was cleared (sign-out) or is
    // empty. Don't switch anyone to "nothing" — reset so the next real
    // selection always re-applies, even if it repeats the last id.
    if (deviceId == null) {
      _lastDeviceId = null;
      return;
    }
    if (deviceId == _lastDeviceId) return;
    _lastDeviceId = deviceId;
    _geyserControl.switchDevice(deviceId);
    _stats.switchDevice(deviceId);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
