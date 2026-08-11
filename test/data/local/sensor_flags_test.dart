import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gs_rework/data/local/prefs_manager.dart';
import 'package:gs_rework/domain/geyser/entities/geyser_settings.dart';

/// Covers the E2 sensor declaration: local mirror defaults/round-trips,
/// per-device scoping, wipe on removal + sign-out, and the RTDB `cs`/`ls`
/// entity parse.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PrefsManager prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await PrefsManager.create();
  });

  group('PrefsManager sensor flags', () {
    const id = 'rtdb-abc';

    test('defaults: current NO, leak NO', () {
      expect(prefs.hasCurrentSensor(id), isFalse);
      expect(prefs.hasLeakSensor(id), isFalse);
    });

    test('set + read round-trip, per device', () async {
      await prefs.setHasCurrentSensor(id, true);
      await prefs.setHasLeakSensor(id, true);
      expect(prefs.hasCurrentSensor(id), isTrue);
      expect(prefs.hasLeakSensor(id), isTrue);
      expect(prefs.hasCurrentSensor('other'), isFalse);
      expect(prefs.hasLeakSensor('other'), isFalse);
    });

    test('removing a device clears its flags', () async {
      await prefs.setHasCurrentSensor(id, true);
      await prefs.setHasLeakSensor(id, true);
      await prefs.removeDevice('AA:BB:CC:DD:EE:FF', id);
      expect(prefs.hasCurrentSensor(id), isFalse);
      expect(prefs.hasLeakSensor(id), isFalse);
    });

    test('sign-out wipe clears flags (no bleed to next account)',
        () async {
      await prefs.setHasCurrentSensor(id, true);
      await prefs.setHasLeakSensor(id, true);
      await prefs.clearDeviceData();
      expect(prefs.hasCurrentSensor(id), isFalse);
      expect(prefs.hasLeakSensor(id), isFalse);
    });
  });

  group('GeyserSettings cs/ls parse', () {
    test('absent keys default false (legacy nodes)', () {
      final s = GeyserSettings.fromMap({'on': true, 'max': 65});
      expect(s.currentSensor, isFalse);
      expect(s.leakSensor, isFalse);
    });

    test('round-trips through toMap', () {
      final s = GeyserSettings.fromMap({'cs': true, 'ls': true});
      expect(s.currentSensor, isTrue);
      expect(s.leakSensor, isTrue);
      final back = GeyserSettings.fromMap(s.toMap());
      expect(back.currentSensor, isTrue);
      expect(back.leakSensor, isTrue);
    });
  });
}
