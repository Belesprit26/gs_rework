import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../core/ble/gatt_uuids.dart';
import '../../core/utils/device_id_generator.dart';
import '../../data/local/prefs_manager.dart';
import '../../data/provisioning/ble_provisioning_repository.dart';
import '../../domain/auth/repositories/auth_repository.dart';
import '../../domain/ble/repositories/ble_repository.dart';
import '../../domain/provisioning/provisioning_status.dart';
import '../device/device_registry_cubit.dart';

part 'provisioning_state.dart';

/// Drives the provisioning modal UI.
///
/// Lifecycle:
/// 1. [init] — reads current device state, detects WiFi, gets Firebase UID.
/// 2. User configures options (BLE/WiFi, nickname, credentials).
/// 3. [submit] — writes changes to the device, listens for status.
/// 4. Terminal status → shows result.
class ProvisioningCubit extends Cubit<ProvisioningState> {
  ProvisioningCubit({
    required BleProvisioningRepository provisioningRepository,
    required AuthRepository authRepository,
    required BleRepository bleRepository,
    required PrefsManager prefsManager,
    required DeviceRegistryCubit deviceRegistry,
  })  : _prov = provisioningRepository,
        _auth = authRepository,
        _ble = bleRepository,
        _prefs = prefsManager,
        _registry = deviceRegistry,
        super(const ProvisioningState());

  final BleProvisioningRepository _prov;
  final AuthRepository _auth;
  final BleRepository _ble;
  final PrefsManager _prefs;
  final DeviceRegistryCubit _registry;
  StreamSubscription<ProvisioningStatus>? _statusSub;
  Timer? _timeout;

  /// Initialize — read device state, auto-detect WiFi SSID, get Firebase UID.
  Future<void> init() async {
    // Get Firebase UID.
    final user = _auth.currentUser();
    final uid = user?.uid;

    // Try to get the current WiFi SSID from the phone.
    String? currentSsid;
    try {
      final info = NetworkInfo();
      currentSsid = await info.getWifiName();
      // Remove surrounding quotes if present (iOS adds them).
      if (currentSsid != null) {
        currentSsid = currentSsid.replaceAll('"', '');
      }
    } catch (_) {
      // Not on WiFi or permission denied — that's fine.
    }

    // Read current device state via BLE.
    String deviceNickname = '';
    String deviceSsid = '';
    bool isWifiConfigured = false;
    bool isProvisioned = false;

    try {
      // Read provisioning status.
      final statusBytes = await _ble.readCharacteristic(GattUuids.provStatus.str);
      final provStatus = statusBytes.isNotEmpty
          ? ProvisioningStatus.fromByte(statusBytes[0])
          : ProvisioningStatus.idle;

      isProvisioned = provStatus.isSuccess;
      isWifiConfigured = provStatus == ProvisioningStatus.complete ||
          provStatus == ProvisioningStatus.wifiOk;

      // Read device nickname.
      final nickBytes = await _ble.readCharacteristic(GattUuids.provDeviceName.str);
      if (nickBytes.isNotEmpty) {
        deviceNickname = utf8.decode(nickBytes);
      }

      // Read stored SSID if WiFi is configured.
      if (isWifiConfigured) {
        try {
          final ssidBytes =
              await _ble.readCharacteristic(GattUuids.provWifiCreds.str);
          if (ssidBytes.isNotEmpty) {
            deviceSsid = utf8.decode(ssidBytes);
          }
        } catch (_) {}
      }

      debugPrint('[Prov] Device state: nick="$deviceNickname", '
          'wifi=$isWifiConfigured, ssid="$deviceSsid", prov=$provStatus');
    } catch (e) {
      debugPrint('[Prov] Could not read device state: $e');
    }

    // For SSID: prefer device-stored, fall back to phone's current WiFi.
    final effectiveSsid = deviceSsid.isNotEmpty
        ? deviceSsid
        : (currentSsid ?? '');

    emit(state.copyWith(
      firebaseUid: uid,
      currentSsid: currentSsid,
      // Pre-fill form with device values.
      deviceNickname: deviceNickname,
      ssid: isWifiConfigured ? effectiveSsid : (currentSsid ?? ''),
      wifiEnabled: isWifiConfigured,
      isAlreadyProvisioned: isProvisioned,
      // Store initial values for change detection.
      initialNickname: deviceNickname,
      initialSsid: effectiveSsid,
      initialWifiEnabled: isWifiConfigured,
    ));
  }

  // ── Form field updates ──────────────────────────────────────────

  void toggleWifi() {
    final enabling = !state.wifiEnabled;
    emit(state.copyWith(
      wifiEnabled: enabling,
      // Pre-fill SSID when enabling if we have one.
      ssid: enabling
          ? (state.initialWifiEnabled
              ? state.initialSsid
              : (state.currentSsid ?? state.ssid))
          : state.ssid,
    ));
  }

  void setDeviceNickname(String value) {
    emit(state.copyWith(deviceNickname: value));
  }

  void setSsid(String value) {
    emit(state.copyWith(ssid: value));
  }

  void setWifiPassword(String value) {
    emit(state.copyWith(wifiPassword: value));
  }

  // ── Submit ──────────────────────────────────────────────────────

  Future<void> submit() async {
    if (!state.canSubmit) return;

    emit(state.copyWith(
      step: ProvisioningStep.inProgress,
      deviceStatus: ProvisioningStatus.idle,
      errorMessage: null,
    ));

    // Listen to status updates from the device.
    _statusSub = _prov.statusStream.listen((status) {
      _timeout?.cancel();
      emit(state.copyWith(deviceStatus: status));

      if (status.isTerminal) {
        emit(state.copyWith(step: ProvisioningStep.result));
      }
    });

    // Safety timeout — if no terminal notification arrives within 30 s,
    // read the status once and transition so the modal doesn't hang.
    _timeout = Timer(const Duration(seconds: 30), () async {
      if (state.step != ProvisioningStep.inProgress) return;
      try {
        final status = await _prov.readStatus();
        emit(state.copyWith(deviceStatus: status, step: ProvisioningStep.result));
      } catch (_) {
        emit(state.copyWith(
          deviceStatus: ProvisioningStatus.error,
          errorMessage: 'Timed out waiting for device response',
          step: ProvisioningStep.result,
        ));
      }
    });

    try {
      // Determine whether to send WiFi credentials.
      bool sendWifi = false;
      if (state.wifiEnabled) {
        if (!state.initialWifiEnabled ||
            state.ssid != state.initialSsid ||
            state.wifiPassword.isNotEmpty) {
          sendWifi = true;
        }
      }

      // Always obtain a Firebase refresh token when WiFi is (or was)
      // enabled.  This must NOT be gated on sendWifi — re-provisioning
      // with unchanged WiFi creds still needs to deliver auth data if
      // a previous attempt failed (e.g. IAM permission was missing).
      String? refreshToken;
      if (state.wifiEnabled || state.initialWifiEnabled) {
        debugPrint('[Prov] Calling createDeviceToken Cloud Function...');
        try {
          final callable = FirebaseFunctions.instance
              .httpsCallable('createDeviceToken');
          final result = await callable.call();
          refreshToken = result.data['refreshToken'] as String?;
          if (refreshToken != null && refreshToken.isNotEmpty) {
            debugPrint('[Prov] Got refresh token (len=${refreshToken.length})');
          } else {
            debugPrint('[Prov] WARNING: Cloud Function returned null/empty token');
          }
        } catch (e) {
          debugPrint('[Prov] CRITICAL: createDeviceToken failed: $e');
          debugPrint('[Prov] Remote mode will NOT work until this is resolved.');
          emit(state.copyWith(remoteSetupFailed: true));
        }
      } else {
        debugPrint('[Prov] WiFi not enabled — skipping Firebase auth');
      }

      // The device ID is derived from the BLE identifier. Without it
      // we cannot assign a unique RTDB identity — abort rather than
      // fall back to a shared ID that would collide across devices.
      final bleMac = _ble.connectedDeviceId;
      if (bleMac == null) {
        _timeout?.cancel();
        emit(state.copyWith(
          step: ProvisioningStep.result,
          deviceStatus: ProvisioningStatus.error,
          errorMessage:
              'Lost connection to the device — reconnect and try again',
        ));
        return;
      }
      final deviceId = deriveDeviceId(bleMac);

      await _prov.provision(
        deviceNickname: state.deviceNickname,
        firebaseUid: state.firebaseUid ?? 'unknown',
        deviceId: deviceId,
        wifiSsid: sendWifi ? state.ssid : null,
        wifiPassword: sendWifi ? state.wifiPassword : null,
        refreshToken: refreshToken,
      );

      await _prefs.setRtdbDeviceId(bleMac, deviceId);
      final nick = state.deviceNickname.isNotEmpty
          ? state.deviceNickname
          : 'My Geyser';
      await _prefs.setDeviceNickname(deviceId, nick);

      _registry.addDevice(DeviceInfo(
        rtdbDeviceId: deviceId,
        bleMac: bleMac,
        nickname: nick,
      ));

      // Best-effort registry write — provisioning has already
      // succeeded on the device, so a Firestore hiccup is logged
      // rather than surfaced as a provisioning failure.
      final uid = state.firebaseUid;
      if (uid != null) {
        try {
          await FirebaseFirestore.instance.doc('users/$uid').set({
            'devices': {
              deviceId: {
                'pairedAt': FieldValue.serverTimestamp(),
                'nickname': nick,
                'bleMac': bleMac,
              }
            },
            'hasDevice': true,
          }, SetOptions(merge: true));
        } catch (e) {
          debugPrint('[Prov] Firestore device registry write failed: $e');
        }
      }
    } catch (e) {
      emit(state.copyWith(
        step: ProvisioningStep.result,
        deviceStatus: ProvisioningStatus.error,
        errorMessage: e.toString(),
      ));
    }
  }

  /// Reset to the configure step (for retry).
  void retry() {
    _statusSub?.cancel();
    _statusSub = null;
    _timeout?.cancel();
    emit(state.copyWith(
      step: ProvisioningStep.configure,
      deviceStatus: ProvisioningStatus.idle,
      errorMessage: null,
    ));
  }

  @override
  Future<void> close() async {
    _timeout?.cancel();
    await _statusSub?.cancel();
    await _prov.dispose();
    return super.close();
  }
}
