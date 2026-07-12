import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../domain/notifications/entities/device_notification.dart';
import '../../domain/telemetry/entities/telemetry_record.dart';

/// Encodes telemetry and notification records to NDJSON and compresses.
///
/// Both record types live in the same cloud chunk, differentiated by the
/// `k` (kind) field:
/// - `"t"` = telemetry
/// - `"n"` = notification
///
/// Field names are kept short to minimize storage costs:
///
/// Telemetry:
/// ```ndjson
/// {"k":"t","pd":"2026-02-12","did":"AA:BB","ts":"...","t":42.5,"on":true,"mn":30,"mx":60}
/// ```
///
/// Notification:
/// ```ndjson
/// {"k":"n","pd":"2026-02-12","did":"AA:BB","ts":"...","tp":1,"tmp":61}
/// ```
abstract final class NdjsonCodec {
  /// Encode telemetry records to NDJSON string.
  static String encodeTelemetry(
    List<TelemetryRecord> records, {
    required String pushDate,
  }) {
    final buffer = StringBuffer();
    for (final r in records) {
      final map = {
        'k': 't',
        'pd': pushDate,
        'did': r.deviceId,
        'ts': r.timestamp.toIso8601String(),
        't': r.temperature,
        'on': r.isOn,
        'mn': r.minTemp,
        'mx': r.maxTemp,
      };
      buffer.writeln(jsonEncode(map));
    }
    return buffer.toString();
  }

  /// Encode notification records to NDJSON string.
  static String encodeNotifications(
    List<DeviceNotification> records, {
    required String pushDate,
  }) {
    final buffer = StringBuffer();
    for (final r in records) {
      final map = {
        'k': 'n',
        'pd': pushDate,
        'did': r.deviceId,
        'ts': r.timestamp.toIso8601String(),
        'tp': r.type.code,
        'tmp': r.temperature,
        'src': r.source == NotificationSource.remote ? 'remote' : 'ble',
      };
      buffer.writeln(jsonEncode(map));
    }
    return buffer.toString();
  }

  /// Compress an NDJSON string to gzipped bytes.
  static Uint8List gzipEncode(String ndjson) {
    final raw = utf8.encode(ndjson);
    final compressed = gzip.encode(raw);
    return Uint8List.fromList(compressed);
  }
}
