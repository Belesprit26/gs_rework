/// Status codes received from the ESP32 provisioning GATT characteristic.
///
/// Must stay in sync with firmware `prov_status_t` enum in wifi_prov.h.
enum ProvisioningStatus {
  /// Waiting for credentials / idle.
  idle(0),

  /// Connecting to WiFi.
  connecting(1),

  /// WiFi connected, IP obtained.
  wifiOk(2),

  /// WiFi connection failed.
  wifiFail(3),

  /// Fully provisioned (WiFi + user bound).
  complete(4),

  /// Unexpected error.
  error(5),

  /// BLE-only provisioning complete (no WiFi).
  bleOnlyOk(6);

  const ProvisioningStatus(this.code);

  /// The uint8 value sent over BLE.
  final int code;

  /// Parse a raw byte from the BLE characteristic.
  static ProvisioningStatus fromByte(int byte) {
    return ProvisioningStatus.values.firstWhere(
      (s) => s.code == byte,
      orElse: () => ProvisioningStatus.error,
    );
  }

  /// Whether this status represents a terminal (finished) state.
  bool get isTerminal =>
      this == complete || this == bleOnlyOk || this == wifiFail || this == error;

  /// Whether this status represents a successful outcome.
  bool get isSuccess => this == complete || this == bleOnlyOk;
}
