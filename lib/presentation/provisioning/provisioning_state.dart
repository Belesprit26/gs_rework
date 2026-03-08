part of 'provisioning_cubit.dart';

/// The current step of the provisioning modal.
enum ProvisioningStep {
  /// User is configuring options (BLE/WiFi chips, nickname, WiFi fields).
  configure,

  /// Provisioning is in progress (writing to device, waiting for status).
  inProgress,

  /// Provisioning finished (success or failure).
  result,
}

class ProvisioningState extends Equatable {
  const ProvisioningState({
    this.step = ProvisioningStep.configure,
    this.wifiEnabled = false,
    this.deviceNickname = '',
    this.ssid = '',
    this.wifiPassword = '',
    this.currentSsid,
    this.deviceStatus = ProvisioningStatus.idle,
    this.errorMessage,
    this.firebaseUid,
    this.isAlreadyProvisioned = false,
    this.initialNickname = '',
    this.initialSsid = '',
    this.initialWifiEnabled = false,
    this.remoteSetupFailed = false,
  });

  final ProvisioningStep step;
  final bool wifiEnabled;
  final String deviceNickname;
  final String ssid;
  final String wifiPassword;

  /// The phone's current WiFi SSID (auto-detected), null if not on WiFi.
  final String? currentSsid;

  /// Real-time status from the device.
  final ProvisioningStatus deviceStatus;

  /// Error message (e.g. BLE write failure).
  final String? errorMessage;

  /// Firebase UID of the logged-in user.
  final String? firebaseUid;

  /// Whether the device was already provisioned before opening the modal.
  final bool isAlreadyProvisioned;

  /// Initial values for change detection.
  final String initialNickname;
  final String initialSsid;
  final bool initialWifiEnabled;

  /// True if the Cloud Function for remote mode auth failed during provisioning.
  final bool remoteSetupFailed;

  // ── Derived helpers ───────────────────────────────────────────────

  /// Whether the nickname is valid (1–16 chars, no spaces).
  bool get isNicknameValid =>
      deviceNickname.isNotEmpty &&
      deviceNickname.length <= 16 &&
      !deviceNickname.contains(' ');

  /// Whether any field changed from the initial (device-stored) values.
  bool get hasChanges {
    if (!isAlreadyProvisioned) return true;
    if (deviceNickname != initialNickname) return true;
    if (wifiEnabled != initialWifiEnabled) return true;
    if (wifiEnabled && ssid != initialSsid) return true;
    if (wifiEnabled && wifiPassword.isNotEmpty) return true;
    // Always allow re-submit when WiFi is enabled so the user can
    // retry auth token delivery if a previous attempt failed.
    if (wifiEnabled && initialWifiEnabled) return true;
    return false;
  }

  /// Whether WiFi credentials will actually be sent (new or changed).
  bool get _willSendWifi {
    if (!wifiEnabled) return false;
    if (!initialWifiEnabled) return true; // Newly enabling WiFi.
    if (ssid != initialSsid) return true; // SSID changed.
    if (wifiPassword.isNotEmpty) return true; // Password changed.
    return false;
  }

  /// Whether the form is ready to submit.
  bool get canSubmit {
    if (!isNicknameValid) return false;
    if (wifiEnabled && ssid.isEmpty) return false;
    // Require password when WiFi creds will actually be sent.
    if (_willSendWifi && wifiPassword.isEmpty) return false;
    if (!hasChanges) return false;
    return true;
  }

  /// Whether the device reported a successful outcome.
  bool get isSuccess => deviceStatus.isSuccess;

  /// A user-friendly label for the current device status.
  String get statusLabel {
    switch (deviceStatus) {
      case ProvisioningStatus.idle:
        return 'Preparing...';
      case ProvisioningStatus.connecting:
        return 'Connecting to WiFi...';
      case ProvisioningStatus.wifiOk:
        return 'WiFi connected!';
      case ProvisioningStatus.wifiFail:
        return 'WiFi connection failed';
      case ProvisioningStatus.complete:
        return 'Setup complete!';
      case ProvisioningStatus.error:
        return 'An error occurred';
      case ProvisioningStatus.bleOnlyOk:
        return 'Setup complete!';
    }
  }

  ProvisioningState copyWith({
    ProvisioningStep? step,
    bool? wifiEnabled,
    String? deviceNickname,
    String? ssid,
    String? wifiPassword,
    String? currentSsid,
    ProvisioningStatus? deviceStatus,
    String? errorMessage,
    String? firebaseUid,
    bool? isAlreadyProvisioned,
    String? initialNickname,
    String? initialSsid,
    bool? initialWifiEnabled,
    bool? remoteSetupFailed,
  }) {
    return ProvisioningState(
      step: step ?? this.step,
      wifiEnabled: wifiEnabled ?? this.wifiEnabled,
      deviceNickname: deviceNickname ?? this.deviceNickname,
      ssid: ssid ?? this.ssid,
      wifiPassword: wifiPassword ?? this.wifiPassword,
      currentSsid: currentSsid ?? this.currentSsid,
      deviceStatus: deviceStatus ?? this.deviceStatus,
      errorMessage: errorMessage,
      firebaseUid: firebaseUid ?? this.firebaseUid,
      isAlreadyProvisioned: isAlreadyProvisioned ?? this.isAlreadyProvisioned,
      initialNickname: initialNickname ?? this.initialNickname,
      initialSsid: initialSsid ?? this.initialSsid,
      initialWifiEnabled: initialWifiEnabled ?? this.initialWifiEnabled,
      remoteSetupFailed: remoteSetupFailed ?? this.remoteSetupFailed,
    );
  }

  @override
  List<Object?> get props => [
        step,
        wifiEnabled,
        deviceNickname,
        ssid,
        wifiPassword,
        currentSsid,
        deviceStatus,
        errorMessage,
        firebaseUid,
        isAlreadyProvisioned,
        initialNickname,
        initialSsid,
        initialWifiEnabled,
        remoteSetupFailed,
      ];
}
