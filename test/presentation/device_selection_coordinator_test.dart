import 'package:flutter_test/flutter_test.dart';
import 'package:gs_rework/data/local/prefs_manager.dart';
import 'package:gs_rework/presentation/device/device_registry_cubit.dart';
import 'package:gs_rework/presentation/device/device_selection_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records switchDevice calls in order, standing in for the real cubits.
class _FakeScoped implements DeviceScoped {
  final calls = <String>[];
  @override
  void switchDevice(String deviceId) => calls.add(deviceId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DeviceRegistryCubit registry;
  late _FakeScoped geyser;
  late _FakeScoped stats;
  late DeviceSelectionCoordinator coordinator;

  Future<void> seed(Map<String, String> macToRtdb) async {
    // getAllDeviceMappings keys on 'rtdb_did_<sanitised-mac>'.
    SharedPreferences.setMockInitialValues({
      for (final e in macToRtdb.entries)
        'rtdb_did_${e.key.replaceAll(':', '_')}': e.value,
    });
    final prefs = await PrefsManager.create();
    registry = DeviceRegistryCubit(prefsManager: prefs);
    geyser = _FakeScoped();
    stats = _FakeScoped();
    coordinator = DeviceSelectionCoordinator(
      registry: registry,
      geyserControl: geyser,
      stats: stats,
    );
  }

  tearDown(() async {
    await coordinator.dispose();
    await registry.close();
  });

  test('start() applies the current selection to both targets', () async {
    await seed({'AA': 'dev-a', 'BB': 'dev-b'});
    coordinator.start();
    expect(geyser.calls, ['dev-a']);
    expect(stats.calls, ['dev-a']);
  });

  test('selecting another device fans out to both', () async {
    await seed({'AA': 'dev-a', 'BB': 'dev-b'});
    coordinator.start();
    registry.selectDevice(1);
    await Future<void>.delayed(Duration.zero); // let the stream deliver
    expect(geyser.calls, ['dev-a', 'dev-b']);
    expect(stats.calls, ['dev-a', 'dev-b']);
  });

  test('selecting the same index again is a no-op (registry-level guard)',
      () async {
    await seed({'AA': 'dev-a', 'BB': 'dev-b'});
    coordinator.start();
    registry.selectDevice(1);
    await Future<void>.delayed(Duration.zero);
    registry.selectDevice(1); // registry emits nothing for a repeat index
    await Future<void>.delayed(Duration.zero);
    expect(geyser.calls, ['dev-a', 'dev-b']);
  });

  test('a nickname change (same selection) does not re-fire', () async {
    await seed({'AA': 'dev-a', 'BB': 'dev-b'});
    coordinator.start();
    registry.updateNickname('dev-a', 'Renamed');
    await Future<void>.delayed(Duration.zero);
    expect(geyser.calls, ['dev-a']); // still just the initial apply
  });

  test('clear() resets the guard so the same id re-applies via addDevice '
      '(the production sign-out → re-provision path)', () async {
    await seed({'AA': 'dev-a'});
    coordinator.start(); // applies dev-a
    registry.clear(); // sign-out: selection → null, guard resets
    await Future<void>.delayed(Duration.zero);
    // Sign-in never re-runs load(); a device reappears via addDevice.
    registry.addDevice(const DeviceInfo(
        rtdbDeviceId: 'dev-a', bleMac: 'AA', nickname: 'A'));
    await Future<void>.delayed(Duration.zero);
    expect(geyser.calls, ['dev-a', 'dev-a']);
    expect(stats.calls, ['dev-a', 'dev-a']);
  });

  test('start() is idempotent', () async {
    await seed({'AA': 'dev-a'});
    coordinator.start();
    coordinator.start();
    expect(geyser.calls, ['dev-a']);
  });
}
