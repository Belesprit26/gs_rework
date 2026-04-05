import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Derives a stable 8-char hex device ID from a BLE MAC address (or
/// iOS CoreBluetooth UUID).
///
/// The same physical device always produces the same ID.  The ID is
/// used as the RTDB path segment (e.g. `gs/{uid}/live/{deviceId}`).
///
/// Format: first 8 hex chars of SHA-256(bleMac.toUpperCase()), lowercase.
/// Collision probability for <1 000 devices per user: negligible.
String deriveDeviceId(String bleMac) {
  final bytes = utf8.encode(bleMac.toUpperCase().trim());
  final hash = sha256.convert(bytes);
  return hash.toString().substring(0, 8);
}
