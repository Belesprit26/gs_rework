import 'package:equatable/equatable.dart';

/// A GeyserSwitch device offered to the user to connect to.
///
/// Usually discovered by an advertisement, but not always: a device that
/// is already connected at the OS level stops advertising and can only be
/// found by asking the platform for its connected peripherals. Those
/// arrive without advertisement data, which is why [rssi] is nullable.
class ScannedDevice extends Equatable {
  const ScannedDevice({
    required this.id,
    required this.name,
    this.rssi,
    this.isConnected = false,
  });

  /// Platform-specific identifier (remoteId on Android/iOS).
  final String id;

  /// Device name — advertised when scanned, the cached GAP name when the
  /// device came from the platform's connected list. The firmware sets
  /// both to the same string, so they are interchangeable here.
  final String name;

  /// Signal strength in dBm (closer to 0 = stronger), or null when the
  /// device was never heard over the air this session.
  ///
  /// Deliberately nullable rather than defaulted: a stand-in value would
  /// sort a device into the signal ranking as though it had been
  /// received, and show a strength the app never measured.
  final int? rssi;

  /// Whether the OS already holds a connection to this device — possibly
  /// on behalf of another app, or left over from a previous run of this
  /// one. Such a device is silent to scanning but connectable.
  final bool isConnected;

  @override
  List<Object?> get props => [id, name, rssi, isConnected];

  @override
  String toString() => 'ScannedDevice($name, $id, '
      '${isConnected ? 'connected' : '${rssi}dBm'})';
}
