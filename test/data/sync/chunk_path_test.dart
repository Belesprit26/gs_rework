import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/data/sync/cloud_storage_sync_repository.dart';

void main() {
  group('CloudStorageSyncRepository.chunkPath', () {
    test('builds sortable per-device object path', () {
      final path = CloudStorageSyncRepository.chunkPath(
        userId: 'uid123',
        deviceId: 'ab12cd34',
        utc: DateTime.utc(2026, 7, 4, 21, 55, 9),
        nonce: 'a3f9',
      );
      expect(
        path,
        'telemetry/uid123/ab12cd34/20260704T215509Z_a3f9.ndjson.gz',
      );
    });

    test('sanitizes MAC-style device IDs (colons → dashes)', () {
      final path = CloudStorageSyncRepository.chunkPath(
        userId: 'uid123',
        deviceId: 'AA:BB:CC:DD:EE:FF',
        utc: DateTime.utc(2026, 1, 2, 3, 4, 5),
        nonce: '0001',
      );
      expect(
        path,
        'telemetry/uid123/AA-BB-CC-DD-EE-FF/20260102T030405Z_0001.ndjson.gz',
      );
      expect(path.contains(':'), isFalse);
    });

    test('timestamps sort lexically in chronological order', () {
      String at(DateTime t) => CloudStorageSyncRepository.chunkPath(
            userId: 'u',
            deviceId: 'd',
            utc: t,
            nonce: '0000',
          );

      final earlier = at(DateTime.utc(2026, 7, 4, 9, 5, 0));
      final later = at(DateTime.utc(2026, 7, 4, 23, 55, 0));
      final nextDay = at(DateTime.utc(2026, 7, 5, 0, 5, 0));

      expect(earlier.compareTo(later), lessThan(0));
      expect(later.compareTo(nextDay), lessThan(0));
    });
  });
}
