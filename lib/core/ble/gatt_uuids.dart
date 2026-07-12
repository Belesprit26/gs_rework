import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// GATT service and characteristic UUIDs for the GeyserSwitch ESP32-C6.
///
/// These are the contract between the mobile app and the firmware.
/// Both sides must agree on these UUIDs for communication to work.
///
/// Base UUID: 47530000-7652-4543-b201-c4b801a6c700
/// "4753" = "GS" in ASCII hex.
abstract final class GattUuids {
  // ── Service ───────────────────────────────────────────────────────
  static final service = Guid('47530001-7652-4543-b201-c4b801a6c700');

  // ── Characteristics ───────────────────────────────────────────────

  /// Real-time temperature in °C × 100 as int16.
  /// Properties: Read, Notify.
  static final temperature = Guid('47530002-7652-4543-b201-c4b801a6c700');

  /// Geyser element state: 0x00 = off, 0x01 = on.
  /// Properties: Read, Write, Notify.
  static final geyserState = Guid('47530003-7652-4543-b201-c4b801a6c700');

  /// Temperature limits: [minTemp, maxTemp, autoReheat] as 3 uint8 bytes.
  /// Properties: Read, Write.
  static final tempLimits = Guid('47530004-7652-4543-b201-c4b801a6c700');

  /// Timer configuration (compact binary).
  /// Properties: Read, Write.
  static final timerConfig = Guid('47530005-7652-4543-b201-c4b801a6c700');

  /// Device info: firmware version string (UTF-8).
  /// Properties: Read.
  static final deviceInfo = Guid('47530006-7652-4543-b201-c4b801a6c700');

  // ── Provisioning Service ──────────────────────────────────────────

  /// Provisioning service UUID.
  static final provService = Guid('47530010-7652-4543-b201-c4b801a6c700');

  /// WiFi credentials — Read (SSID only), Write ("ssid\0password").
  /// Read returns the stored SSID. Write format: null-separated UTF-8.
  static final provWifiCreds = Guid('47530011-7652-4543-b201-c4b801a6c700');

  /// User binding — Write only.
  /// Format: Firebase UID string (UTF-8).
  /// Writing this triggers the provisioning sequence on the device.
  static final provUserBind = Guid('47530012-7652-4543-b201-c4b801a6c700');

  /// Provisioning status — Read, Notify.
  /// Format: uint8 — 0=idle, 1=connecting, 2=wifi_ok, 3=wifi_fail,
  ///                 4=complete, 5=error, 6=ble_only_ok.
  static final provStatus = Guid('47530013-7652-4543-b201-c4b801a6c700');

  /// Device nickname — Read, Write.
  /// Format: UTF-8, max 16 chars. Appended to "GeyserSwitch-" for
  /// the advertising name (e.g. "GeyserSwitch-James").
  static final provDeviceName = Guid('47530014-7652-4543-b201-c4b801a6c700');

  /// Firebase auth data — Write only.
  /// Format: "refreshToken\0deviceId" (null-separated UTF-8).
  /// The app exchanges a custom token for a refresh token, then
  /// writes it here so the ESP can authenticate to RTDB.
  static final provAuthData = Guid('47530015-7652-4543-b201-c4b801a6c700');

  // ── Time Sync ────────────────────────────────────────────────────

  /// Time sync — Write only.
  /// Format: uint32 LE — Unix timestamp (seconds since epoch, UTC).
  /// Phone pushes its current time once per BLE connection cycle.
  static final timeSync = Guid('47530008-7652-4543-b201-c4b801a6c700');

  // ── Events & Buffers ──────────────────────────────────────────

  /// Device events — Read (buffered), Notify (real-time).
  /// Read: N × 6 bytes [type, temp, ts0..ts3 LE].
  /// Notify: 2 bytes [type, temp] for real-time events.
  static final deviceEvents = Guid('47530009-7652-4543-b201-c4b801a6c700');

  /// Telemetry buffer — Read.
  /// N × 10 bytes [temp_i16_le, relay, min, max, auto_reheat, ts_u32_le].
  static final telemetryBuffer = Guid('4753000a-7652-4543-b201-c4b801a6c700');

  /// Buffer acknowledge — Write.
  /// Write any byte to clear both event and telemetry buffers on the ESP.
  static final bufferAck = Guid('4753000b-7652-4543-b201-c4b801a6c700');

  /// Stored device ID — Read only, unencrypted.
  /// Returns the RTDB device ID (e.g. "a3f9b21c") from the ESP's NVS.
  /// Used for iOS re-pairing: when the Core Bluetooth UUID changes, the
  /// app reads this to recover the existing RTDB mapping instead of
  /// creating a new device ID.
  static final storedDeviceId = Guid('4753000c-7652-4543-b201-c4b801a6c700');

  /// Max-on safety timer — Read, Write (encrypted).
  /// Format: uint16 LE — minutes (0 = disabled).
  static final maxOnTimer = Guid('4753000d-7652-4543-b201-c4b801a6c700');

  // ── Owner lock ───────────────────────────────────────────────────

  /// Owner auth — Read (challenge), Write (response), encrypted.
  /// Read returns a fresh 16-byte nonce; write the 32-byte
  /// HMAC-SHA256(ownerKey, nonce) to unlock this connection.
  /// Gated writes fail with ATT "insufficient authorization" until
  /// unlocked.
  static final ownerAuth = Guid('4753000e-7652-4543-b201-c4b801a6c700');

  /// Owner key — Write only (encrypted), provisioning service.
  /// Exactly 32 random bytes. Written at provisioning (open while the
  /// device is unprovisioned) and on key rotation (requires unlock).
  static final provOwnerKey = Guid('47530016-7652-4543-b201-c4b801a6c700');
}
