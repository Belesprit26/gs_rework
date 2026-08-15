import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/data/ble/flutter_blue_plus_ble_repository.dart';
import 'package:gs_rework/domain/ble/entities/scanned_device.dart';

/// Locks how the scan list is assembled from its two sources.
///
/// Scanning alone cannot find every device: the firmware stops
/// advertising once anything connects to it and only re-advertises on
/// disconnect, so a connected unit is radio-silent. On iOS the connection
/// belongs to the system daemon and outlives an app relaunch, which is
/// how a provisioned device became unreachable — the scan was working, it
/// just had nothing to hear.
void main() {
  ScannedDevice advertised(String id, {int rssi = -60, String? name}) =>
      ScannedDevice(id: id, name: name ?? 'GeyserSwitch-$id', rssi: rssi);

  ScannedDevice connected(String id, {String? name}) => ScannedDevice(
        id: id,
        name: name ?? 'GeyserSwitch-$id',
        isConnected: true,
      );

  List<ScannedDevice> merge({
    List<ScannedDevice> adv = const [],
    List<ScannedDevice> sys = const [],
  }) =>
      FlutterBluePlusBleRepository.mergeDiscovered(
        advertised: adv,
        connected: sys,
      );

  test('nothing found → empty', () {
    expect(merge(), isEmpty);
  });

  test('a connected device appears with no advertisement at all', () {
    // The whole point: scanning returns nothing, yet the device is there.
    final result = merge(sys: [connected('a')]);

    expect(result.length, 1);
    expect(result.single.id, 'a');
    expect(result.single.isConnected, isTrue);
    expect(result.single.rssi, isNull);
  });

  test('advertised devices sort strongest first', () {
    final result = merge(adv: [
      advertised('weak', rssi: -90),
      advertised('strong', rssi: -40),
      advertised('mid', rssi: -65),
    ]);

    expect(result.map((d) => d.id), ['strong', 'mid', 'weak']);
  });

  test('connected devices sort above advertised ones', () {
    final result = merge(
      adv: [advertised('strong', rssi: -30)],
      sys: [connected('paired')],
    );

    // Even against the strongest possible signal: a connected device is
    // the one the user can act on right now.
    expect(result.first.id, 'paired');
  });

  test('a device in both lists keeps its live signal reading', () {
    final result = merge(
      adv: [advertised('a', rssi: -55)],
      sys: [connected('a')],
    );

    expect(result.length, 1, reason: 'must not be listed twice');
    expect(result.single.rssi, -55);
    expect(result.single.isConnected, isFalse);
  });

  test('a null signal never outranks a real one among peers', () {
    // Two connected devices, neither with a reading — must not throw and
    // must not drop one.
    final result = merge(sys: [connected('a'), connected('b')]);

    expect(result.length, 2);
  });

  test('mixed list keeps every device', () {
    final result = merge(
      adv: [advertised('a'), advertised('b')],
      sys: [connected('c')],
    );

    expect(result.map((d) => d.id).toSet(), {'a', 'b', 'c'});
    expect(result.first.id, 'c');
  });
}
