import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/data/sync/ndjson_codec.dart';
import 'package:gs_rework/domain/notifications/entities/device_notification.dart';
import 'package:gs_rework/domain/telemetry/entities/telemetry_record.dart';

void main() {
  final ts = DateTime.utc(2026, 7, 4, 21, 55);

  group('NdjsonCodec.encodeTelemetry', () {
    test('emits one JSON line per record with short field names', () {
      final ndjson = NdjsonCodec.encodeTelemetry(
        [
          TelemetryRecord(
            deviceId: 'ab12cd34',
            timestamp: ts,
            temperature: 42.5,
            isOn: true,
            minTemp: 30,
            maxTemp: 60,
          ),
        ],
        pushDate: '2026-07-04',
      );

      final lines = ndjson.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines, hasLength(1));

      final map = jsonDecode(lines.first) as Map<String, dynamic>;
      expect(map['k'], 't');
      expect(map['pd'], '2026-07-04');
      expect(map['did'], 'ab12cd34');
      expect(map['ts'], ts.toIso8601String());
      expect(map['t'], 42.5);
      expect(map['on'], true);
      expect(map['mn'], 30);
      expect(map['mx'], 60);
    });
  });

  group('NdjsonCodec.encodeNotifications', () {
    test('emits kind "n" with type code and source', () {
      final ndjson = NdjsonCodec.encodeNotifications(
        [
          DeviceNotification(
            deviceId: 'ab12cd34',
            type: NotificationType.fromCode(1),
            temperature: 61,
            timestamp: ts,
            source: NotificationSource.remote,
          ),
        ],
        pushDate: '2026-07-04',
      );

      final map = jsonDecode(ndjson.trim()) as Map<String, dynamic>;
      expect(map['k'], 'n');
      expect(map['tp'], 1);
      expect(map['tmp'], 61);
      expect(map['src'], 'remote');
    });
  });

  group('NdjsonCodec.gzipEncode', () {
    test('round-trips through gzip', () {
      const original = '{"k":"t","t":42.5}\n{"k":"n","tp":1}\n';
      final compressed = NdjsonCodec.gzipEncode(original);
      final restored = utf8.decode(gzip.decode(compressed));
      expect(restored, original);
    });
  });
}
