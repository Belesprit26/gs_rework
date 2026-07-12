import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/core/ble/owner_auth_codec.dart';

void main() {
  group('computeUnlockResponse (HMAC-SHA256)', () {
    // RFC 4231 test case 2 — the SAME vector asserted in the firmware
    // (owner_auth.c). If either side changes algorithm/encoding, one of
    // these two tests fails and the mismatch is caught before the bench.
    test('matches RFC 4231 case 2 (shared firmware vector)', () {
      final key = Uint8List.fromList(utf8.encode('Jefe'));
      final data =
          Uint8List.fromList(utf8.encode('what do ya want for nothing?'));

      final mac = computeUnlockResponse(key: key, nonce: data);

      final hex = mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(
        hex,
        '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843',
      );
    });

    test('output is 32 bytes and deterministic', () {
      final key = generateOwnerKey();
      final nonce = Uint8List.fromList(List.filled(ownerNonceLength, 7));

      final a = computeUnlockResponse(key: key, nonce: nonce);
      final b = computeUnlockResponse(key: key, nonce: nonce);

      expect(a.length, 32);
      expect(a, b);
    });

    test('different nonce → different response (replay resistance)', () {
      final key = generateOwnerKey();
      final n1 = Uint8List.fromList(List.filled(ownerNonceLength, 1));
      final n2 = Uint8List.fromList(List.filled(ownerNonceLength, 2));

      expect(
        computeUnlockResponse(key: key, nonce: n1),
        isNot(computeUnlockResponse(key: key, nonce: n2)),
      );
    });
  });

  group('generateOwnerKey', () {
    test('produces 32 random bytes', () {
      expect(generateOwnerKey(), hasLength(ownerKeyLength));
    });

    test('two keys differ', () {
      // Astronomically unlikely to collide; guards against a constant.
      expect(generateOwnerKey(), isNot(generateOwnerKey()));
    });
  });
}
