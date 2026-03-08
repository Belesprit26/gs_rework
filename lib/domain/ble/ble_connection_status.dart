/// Represents the BLE connection lifecycle.
///
/// Maps to the connection state machine:
///
/// ```
/// disconnected → scanning → connecting → discoveringServices → ready
///      ↑                                                         |
///      └──────────── reconnecting ←──────────────────────────────┘
/// ```
enum BleConnectionStatus {
  /// No device paired or not attempting to connect.
  disconnected,

  /// Actively scanning for devices.
  scanning,

  /// Found device, establishing BLE connection.
  connecting,

  /// Connected, discovering GATT services and characteristics.
  discoveringServices,

  /// Fully connected, services discovered, ready for read/write/notify.
  ready,

  /// Was connected, lost connection, automatically reconnecting.
  reconnecting,
}
