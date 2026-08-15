import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/domain/ble/ble_connection_status.dart';
import 'package:gs_rework/presentation/ble/ble_connection_cubit.dart';
import 'package:gs_rework/presentation/dashboard/connectivity_badge.dart';
import 'package:gs_rework/presentation/geyser/geyser_control_cubit.dart';

/// Locks the per-transport reasons shown in the connectivity hub.
///
/// The combined status answers "am I in contact". These answer "why not,
/// and which half is at fault" — the question behind the field report
/// that switching between WiFi and BLE gave no visible reason when it
/// failed. Every `down` reason must name something the user can act on.
void main() {
  group('bluetoothTransportStatus', () {
    test('BLE mode → active', () {
      final s = bluetoothTransportStatus(
        const GeyserControlState(mode: GeyserMode.ble),
        const BleConnectionState(),
      );
      expect(s.state, TransportState.active);
    });

    test('a connection attempt in flight → standby, not down', () {
      final s = bluetoothTransportStatus(
        const GeyserControlState(
          mode: GeyserMode.offline,
          bleStatus: BleConnectionStatus.connecting,
        ),
        const BleConnectionState(isBluetoothOn: true),
      );
      expect(s.state, TransportState.standby);
      expect(s.detail, contains('connecting'));
    });

    test('reconnecting counts as in flight too', () {
      final s = bluetoothTransportStatus(
        const GeyserControlState(
          mode: GeyserMode.offline,
          bleStatus: BleConnectionStatus.reconnecting,
        ),
        const BleConnectionState(isBluetoothOn: true),
      );
      expect(s.state, TransportState.standby);
    });

    test('radio off → down, and says to turn it on', () {
      final s = bluetoothTransportStatus(
        const GeyserControlState(mode: GeyserMode.offline),
        const BleConnectionState(isBluetoothOn: false),
      );
      expect(s.state, TransportState.down);
      expect(s.detail.toLowerCase(), contains('bluetooth on'));
    });

    test('radio on but nothing paired → down, and points at pairing', () {
      final s = bluetoothTransportStatus(
        const GeyserControlState(mode: GeyserMode.offline),
        const BleConnectionState(isBluetoothOn: true),
      );
      expect(s.state, TransportState.down);
      expect(s.detail.toLowerCase(), contains('pair'));
    });

    test('paired and radio on but not connected → out of range', () {
      final s = bluetoothTransportStatus(
        const GeyserControlState(mode: GeyserMode.offline),
        const BleConnectionState(
          isBluetoothOn: true,
          pairedDeviceId: 'AA:BB',
        ),
      );
      expect(s.state, TransportState.down);
      expect(s.detail.toLowerCase(), contains('range'));
    });
  });

  group('wifiTransportStatus', () {
    test('remote mode with a fresh heartbeat → active', () {
      final s = wifiTransportStatus(
        const GeyserControlState(mode: GeyserMode.remote),
        const BleConnectionState(isWifiProvisioned: true),
      );
      expect(s.state, TransportState.active);
    });

    test('device never set up for WiFi → down, and points at Configure', () {
      final s = wifiTransportStatus(
        const GeyserControlState(mode: GeyserMode.ble),
        const BleConnectionState(),
      );
      expect(s.state, TransportState.down);
      expect(s.detail.toLowerCase(), contains('configure'));
    });

    test('provisioned but not reporting → down, and says so', () {
      final s = wifiTransportStatus(
        const GeyserControlState(
          mode: GeyserMode.remote,
          deviceOffline: true,
        ),
        const BleConnectionState(isWifiProvisioned: true),
      );
      expect(s.state, TransportState.down);
      expect(s.detail.toLowerCase(), contains('reported'));
    });

    test('provisioned and healthy but BLE has the floor → standby', () {
      // The case that reads as a bug: WiFi is fine, it just is not the
      // path in use, because Bluetooth is preferred whenever present.
      final s = wifiTransportStatus(
        const GeyserControlState(mode: GeyserMode.ble),
        const BleConnectionState(isWifiProvisioned: true),
      );
      expect(s.state, TransportState.standby);
    });
  });

  test('no transport ever reports a reason the user cannot act on', () {
    final states = <TransportStatus>[
      bluetoothTransportStatus(
        const GeyserControlState(mode: GeyserMode.offline),
        const BleConnectionState(),
      ),
      wifiTransportStatus(
        const GeyserControlState(mode: GeyserMode.offline),
        const BleConnectionState(),
      ),
    ];

    for (final s in states) {
      expect(s.detail, isNotEmpty);
      expect(s.detail.toLowerCase(), isNot(equals('unavailable')));
    }
  });
}
