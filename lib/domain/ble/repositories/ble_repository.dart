import 'dart:typed_data';

import '../ble_connection_status.dart';
import '../entities/scanned_device.dart';

/// Domain contract for BLE operations.
///
/// Phase 1: connection lifecycle (scan, connect, reconnect).
/// Phase 2: characteristic read/write/notify.
abstract class BleRepository {
  // ── Connection state ──────────────────────────────────────────────

  /// Stream of connection status changes.
  Stream<BleConnectionStatus> get connectionStatus;

  /// Current connection status (synchronous snapshot).
  BleConnectionStatus get currentStatus;

  // ── Scanning ──────────────────────────────────────────────────────

  /// Start scanning for GeyserSwitch devices.
  /// Returns a stream of discovered devices (accumulative list).
  Stream<List<ScannedDevice>> startScan({Duration timeout});

  /// Stop an active scan.
  Future<void> stopScan();

  // ── Connection ────────────────────────────────────────────────────

  /// Connect to a specific device by its [deviceId].
  /// Discovers services automatically after connection.
  Future<void> connect(String deviceId);

  /// Disconnect from the current device.
  Future<void> disconnect();

  // ── Paired device ─────────────────────────────────────────────────

  /// The ID of the currently connected device, or null.
  String? get connectedDeviceId;

  /// Whether BLE is supported and enabled on this device.
  Future<bool> get isAvailable;

  /// Whether the Bluetooth adapter is currently on.
  bool get isAdapterOn;

  /// Stream that emits `true` when Bluetooth is turned on, `false` when off.
  Stream<bool> get adapterState;

  // ── Characteristic operations (Phase 2) ───────────────────────────

  /// Read raw bytes from a characteristic identified by [characteristicId].
  /// The [characteristicId] is the UUID string of the characteristic.
  Future<Uint8List> readCharacteristic(String characteristicId);

  /// Write raw bytes to a characteristic identified by [characteristicId].
  Future<void> writeCharacteristic(String characteristicId, Uint8List value);

  /// Subscribe to notifications on a characteristic.
  /// Returns a stream of raw byte payloads each time the ESP32 notifies.
  Stream<Uint8List> subscribe(String characteristicId);

  /// Unsubscribe from notifications on a characteristic.
  Future<void> unsubscribe(String characteristicId);

  // ── Cleanup ───────────────────────────────────────────────────────

  /// Release all resources (subscriptions, connections).
  Future<void> dispose();
}
