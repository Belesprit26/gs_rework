import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gs_rework/data/local/prefs_manager.dart';

/// Covers the per-device "Heat for a time" state: enter/exit round-trips,
/// per-device scoping, and — critically — that it is wiped on device
/// removal and on sign-out so nothing bleeds into the next account.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PrefsManager prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await PrefsManager.create();
  });

  group('PrefsManager heat mode', () {
    const id = 'rtdb-abc';

    test('defaults to temperature mode with no saved limits', () {
      expect(prefs.isTimeHeatMode(id), isFalse);
      expect(prefs.savedHeatMax(id), isNull);
      expect(prefs.savedHeatAutoReheat(id), isNull);
    });

    test('enable stores the flag and the limits to restore', () async {
      await prefs.enableTimeHeatMode(id, savedMax: 55, savedAutoReheat: true);
      expect(prefs.isTimeHeatMode(id), isTrue);
      expect(prefs.savedHeatMax(id), 55);
      expect(prefs.savedHeatAutoReheat(id), isTrue);
    });

    test('disable clears the flag and the saved limits', () async {
      await prefs.enableTimeHeatMode(id, savedMax: 55, savedAutoReheat: true);
      await prefs.disableTimeHeatMode(id);
      expect(prefs.isTimeHeatMode(id), isFalse);
      expect(prefs.savedHeatMax(id), isNull);
      expect(prefs.savedHeatAutoReheat(id), isNull);
    });

    test('state is scoped per device', () async {
      await prefs.enableTimeHeatMode('a', savedMax: 52, savedAutoReheat: false);
      expect(prefs.isTimeHeatMode('a'), isTrue);
      expect(prefs.isTimeHeatMode('b'), isFalse);
      expect(prefs.savedHeatMax('b'), isNull);
    });

    test('sign-out wipe removes heat-mode state (no bleed to next account)',
        () async {
      await prefs.enableTimeHeatMode(id, savedMax: 55, savedAutoReheat: true);
      await prefs.clearDeviceData();
      expect(prefs.isTimeHeatMode(id), isFalse);
      expect(prefs.savedHeatMax(id), isNull);
      expect(prefs.savedHeatAutoReheat(id), isNull);
    });

    test('removing a device clears its heat-mode state', () async {
      await prefs.enableTimeHeatMode(id, savedMax: 55, savedAutoReheat: true);
      await prefs.removeDevice('AA:BB:CC:DD:EE:FF', id);
      expect(prefs.isTimeHeatMode(id), isFalse);
      expect(prefs.savedHeatMax(id), isNull);
    });
  });
}
