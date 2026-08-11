import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/presentation/provisioning/provisioning_cubit.dart';

/// Locks the app-side validators to the firmware's ACTUAL acceptance
/// rules (wifi_prov.c): nickname ≤ 16 UTF-8 BYTES (not characters),
/// SSID ≤ 32 bytes, password 8–63 bytes. See
/// documentation/APP_FIRMWARE_CONTRACT.md.
void main() {
  group('isNicknameValid — byte-true mirror of PROV_NICKNAME_MAX', () {
    ProvisioningState withNick(String n) =>
        ProvisioningState(deviceNickname: n);

    test('16 ASCII chars (16 bytes) valid', () {
      expect(withNick('ABCDEFGHIJKLMNOP').isNicknameValid, isTrue);
    });

    test('17 ASCII chars invalid', () {
      expect(withNick('ABCDEFGHIJKLMNOPQ').isNicknameValid, isFalse);
    });

    test('5 emoji (20 bytes) invalid despite being ≤16 characters', () {
      expect(withNick('🔥🔥🔥🔥🔥').isNicknameValid, isFalse);
    });

    test('legacy accented name within 16 bytes stays valid', () {
      // "Zoë" = 4 UTF-8 bytes — firmware accepted it historically and
      // still would; only the input filter steers NEW names to ASCII.
      expect(withNick('Zoë').isNicknameValid, isTrue);
    });

    test('whitespace and empty invalid', () {
      expect(withNick('two words').isNicknameValid, isFalse);
      expect(withNick('').isNicknameValid, isFalse);
    });
  });

  group('canSubmit — SSID/password byte bounds (WPA2 + firmware buffers)',
      () {
    ProvisioningState wifi({String ssid = 'Home', String pass = 'password1'}) {
      return ProvisioningState(
        deviceNickname: 'Geyser',
        wifiEnabled: true,
        ssid: ssid,
        wifiPassword: pass,
      );
    }

    test('valid creds submit', () {
      expect(wifi().canSubmit, isTrue);
    });

    test('password below WPA2 minimum (8) refused', () {
      expect(wifi(pass: '1234567').canSubmit, isFalse);
    });

    test('password at bounds 8 and 63 accepted, 64 refused', () {
      expect(wifi(pass: 'a' * 8).canSubmit, isTrue);
      expect(wifi(pass: 'a' * 63).canSubmit, isTrue);
      expect(wifi(pass: 'a' * 64).canSubmit, isFalse);
    });

    test('SSID over 32 bytes refused (firmware truncates at 32)', () {
      expect(wifi(ssid: 's' * 32).canSubmit, isTrue);
      expect(wifi(ssid: 's' * 33).canSubmit, isFalse);
    });

    test('BLE-only (wifi disabled) needs no password', () {
      const s = ProvisioningState(deviceNickname: 'Geyser');
      expect(s.canSubmit, isTrue);
    });
  });
}
