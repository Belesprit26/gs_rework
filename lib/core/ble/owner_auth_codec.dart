/// Pure crypto helpers for the BLE owner-lock (characteristics 0x0E/0x16).
///
/// The firmware side (`owner_auth.c`, mbedtls) computes the same
/// HMAC-SHA256 — both implementations are pinned to the RFC 4231
/// test vector in `test/core/ble/owner_auth_codec_test.dart`.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Owner key length in bytes (matches firmware OWNER_KEY_LEN).
const int ownerKeyLength = 32;

/// Challenge nonce length in bytes (matches firmware OWNER_NONCE_LEN).
const int ownerNonceLength = 16;

/// Compute the unlock response: HMAC-SHA256(key, nonce).
Uint8List computeUnlockResponse({
  required Uint8List key,
  required Uint8List nonce,
}) {
  final digest = Hmac(sha256, key).convert(nonce);
  return Uint8List.fromList(digest.bytes);
}

/// Generate a new random 32-byte owner key.
Uint8List generateOwnerKey({Random? random}) {
  final rng = random ?? Random.secure();
  return Uint8List.fromList(
    List<int>.generate(ownerKeyLength, (_) => rng.nextInt(256)),
  );
}
