import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/domain/ble/ble_connection_status.dart';
import 'package:gs_rework/presentation/ble/ble_connection_cubit.dart';
import 'package:gs_rework/presentation/dashboard/connectivity_badge.dart';
import 'package:gs_rework/presentation/geyser/geyser_control_cubit.dart';

/// Locks the connectivity mapper to the six states the legacy _ModeBanner
/// rendered, including its precedence (connecting outranks Bluetooth-off).
/// The banner is gone; this is the contract that nothing it could say
/// was lost in the move to the rail badge.
void main() {
  group('connectivityStatusFrom — the six legacy banner states', () {
    test('1. BLE mode → ble', () {
      expect(
        connectivityStatusFrom(
          const GeyserControlState(mode: GeyserMode.ble),
          const BleConnectionState(),
        ),
        ConnectivityStatus.ble,
      );
    });

    test('2. remote + fresh heartbeat → wifi', () {
      expect(
        connectivityStatusFrom(
          const GeyserControlState(mode: GeyserMode.remote),
          const BleConnectionState(),
        ),
        ConnectivityStatus.wifi,
      );
    });

    test('3. remote + stale → deviceOffline', () {
      expect(
        connectivityStatusFrom(
          const GeyserControlState(
            mode: GeyserMode.remote,
            deviceOffline: true,
          ),
          const BleConnectionState(),
        ),
        ConnectivityStatus.deviceOffline,
      );
    });

    test('4. offline + BLE attempt in flight → connecting '
        '(all three busy statuses)', () {
      for (final s in [
        BleConnectionStatus.connecting,
        BleConnectionStatus.discoveringServices,
        BleConnectionStatus.reconnecting,
      ]) {
        expect(
          connectivityStatusFrom(
            GeyserControlState(mode: GeyserMode.offline, bleStatus: s),
            const BleConnectionState(),
          ),
          ConnectivityStatus.connecting,
          reason: 'bleStatus=$s',
        );
      }
    });

    test('4b. connecting outranks Bluetooth-off (legacy precedence)', () {
      expect(
        connectivityStatusFrom(
          const GeyserControlState(
            mode: GeyserMode.offline,
            bleStatus: BleConnectionStatus.reconnecting,
          ),
          const BleConnectionState(isBluetoothOn: false),
        ),
        ConnectivityStatus.connecting,
      );
    });

    test('5. offline + Bluetooth off → btOff', () {
      expect(
        connectivityStatusFrom(
          const GeyserControlState(mode: GeyserMode.offline),
          const BleConnectionState(isBluetoothOn: false),
        ),
        ConnectivityStatus.btOff,
      );
    });

    test('6. offline + Bluetooth on, idle → notConnected', () {
      expect(
        connectivityStatusFrom(
          const GeyserControlState(mode: GeyserMode.offline),
          const BleConnectionState(isBluetoothOn: true),
        ),
        ConnectivityStatus.notConnected,
      );
    });

    test('the orange family is exactly the three down states', () {
      const down = {
        ConnectivityStatus.deviceOffline,
        ConnectivityStatus.btOff,
        ConnectivityStatus.notConnected,
      };
      for (final s in ConnectivityStatus.values) {
        expect(s.isDown, down.contains(s), reason: '$s');
      }
    });
  });

  group('duration formatting', () {
    test('compactAgo buckets', () {
      expect(compactAgo(const Duration(seconds: 45)), 'now');
      expect(compactAgo(const Duration(minutes: 4)), '4m');
      expect(compactAgo(const Duration(minutes: 59)), '59m');
      expect(compactAgo(const Duration(hours: 2, minutes: 10)), '2h');
      expect(compactAgo(const Duration(hours: 23)), '23h');
      expect(compactAgo(const Duration(days: 3, hours: 4)), '3d');
    });

    test('sentenceAgo buckets', () {
      final now = DateTime.now();
      expect(sentenceAgo(now), 'just now');
      expect(
        sentenceAgo(now.subtract(const Duration(minutes: 4))),
        '4 m ago',
      );
      expect(sentenceAgo(now.subtract(const Duration(hours: 2))), '2 h ago');
      expect(sentenceAgo(now.subtract(const Duration(days: 3))), '3 d ago');
    });
  });
}
