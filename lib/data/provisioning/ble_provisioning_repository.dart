import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/ble/gatt_uuids.dart';
import '../../domain/ble/repositories/ble_repository.dart';
import '../../domain/provisioning/provisioning_status.dart';

/// Handles the BLE provisioning protocol with the ESP32 firmware.
///
/// Writes WiFi credentials, user binding, and device nickname to the
/// provisioning GATT service, and subscribes to status notifications.
class BleProvisioningRepository {
  BleProvisioningRepository({required BleRepository bleRepository})
      : _ble = bleRepository;

  final BleRepository _ble;
  StreamSubscription<Uint8List>? _statusSub;
  final _statusController = StreamController<ProvisioningStatus>.broadcast();

  /// Stream of provisioning status updates from the device.
  Stream<ProvisioningStatus> get statusStream => _statusController.stream;

  /// Subscribe to provisioning status notifications from the device.
  void listenToStatus() {
    _statusSub?.cancel();
    _statusSub = _ble.subscribe(GattUuids.provStatus.str).listen(
      (bytes) {
        if (bytes.isNotEmpty) {
          final status = ProvisioningStatus.fromByte(bytes[0]);
          debugPrint('[Prov] Status notification: $status (${bytes[0]})');
          if (!_statusController.isClosed) {
            _statusController.add(status);
          }
        }
      },
      onError: (Object e) {
        debugPrint('[Prov] Status subscription error: $e');
      },
    );
  }

  /// Write the device nickname (max 16 chars, matching PROV_NICKNAME_MAX).
  Future<void> writeDeviceName(String nickname) async {
    final trimmed = nickname.length > 16 ? nickname.substring(0, 16) : nickname;
    final bytes = Uint8List.fromList(utf8.encode(trimmed));
    await _ble.writeCharacteristic(GattUuids.provDeviceName.str, bytes);
    debugPrint('[Prov] Device name written: "$trimmed"');
  }

  /// Write WiFi credentials as "ssid\0password".
  Future<void> writeWifiCredentials({
    required String ssid,
    required String password,
  }) async {
    final payload = '$ssid\x00$password';
    final bytes = Uint8List.fromList(utf8.encode(payload));
    await _ble.writeCharacteristic(GattUuids.provWifiCreds.str, bytes);
    debugPrint('[Prov] WiFi credentials written (SSID="$ssid")');
  }

  /// Write the Firebase UID — this triggers the provisioning sequence
  /// on the device. If WiFi creds were written first, the device will
  /// attempt WiFi connection. Otherwise it does BLE-only provisioning.
  Future<void> writeUserBinding(String uid) async {
    final bytes = Uint8List.fromList(utf8.encode(uid));
    await _ble.writeCharacteristic(GattUuids.provUserBind.str, bytes);
    debugPrint('[Prov] User binding written (UID="$uid")');
  }

  /// Read the current provisioning status.
  Future<ProvisioningStatus> readStatus() async {
    final bytes = await _ble.readCharacteristic(GattUuids.provStatus.str);
    if (bytes.isEmpty) return ProvisioningStatus.idle;
    return ProvisioningStatus.fromByte(bytes[0]);
  }

  /// Write Firebase auth data (refresh token + device ID).
  /// Format: "refreshToken\0deviceId" — the ESP stores these in NVS
  /// for authenticating to Firebase RTDB.
  Future<void> writeAuthData({
    required String refreshToken,
    required String deviceId,
  }) async {
    final payload = '$refreshToken\x00$deviceId';
    final bytes = Uint8List.fromList(utf8.encode(payload));
    await _ble.writeCharacteristic(GattUuids.provAuthData.str, bytes);
    debugPrint('[Prov] Auth data written (deviceId="$deviceId", '
        'tokenLen=${refreshToken.length})');
  }

  /// Run the full provisioning sequence.
  ///
  /// 1. Write device nickname
  /// 2. If [wifiSsid] is provided, write WiFi credentials
  /// 3. If [refreshToken] is provided, write Firebase auth data
  /// 4. Write user binding (triggers provisioning on device)
  Future<void> provision({
    required String deviceNickname,
    required String firebaseUid,
    String? wifiSsid,
    String? wifiPassword,
    String? refreshToken,
    required String deviceId,
  }) async {
    // 1. Subscribe to status first, so we don't miss notifications.
    listenToStatus();

    // 2. Write nickname.
    await writeDeviceName(deviceNickname);

    // 3. Write WiFi creds if opted in.
    if (wifiSsid != null && wifiSsid.isNotEmpty) {
      await writeWifiCredentials(
        ssid: wifiSsid,
        password: wifiPassword ?? '',
      );
    }

    // 4. Write Firebase auth data if WiFi + token available.
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await writeAuthData(refreshToken: refreshToken, deviceId: deviceId);
    }

    // 5. Write user binding — triggers the sequence.
    await writeUserBinding(firebaseUid);
  }

  /// Clean up subscriptions.
  Future<void> dispose() async {
    await _statusSub?.cancel();
    _statusSub = null;
    await _statusController.close();
  }
}
