import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:gs_rework/data/sync/sync_lock.dart';

void main() {
  late Directory tempDir;
  late File lockFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sync_lock_test');
    lockFile = File('${tempDir.path}/telemetry_sync.lock');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('acquires when no lock exists', () async {
    final lock = SyncLock(lockFile);
    expect(await lock.tryAcquire(), isTrue);
    expect(lockFile.existsSync(), isTrue);
  });

  test('second contender is refused while lock is fresh', () async {
    final holder = SyncLock(lockFile);
    final contender = SyncLock(lockFile);

    expect(await holder.tryAcquire(), isTrue);
    expect(await contender.tryAcquire(), isFalse);
  });

  test('release allows re-acquisition', () async {
    final lock = SyncLock(lockFile);
    expect(await lock.tryAcquire(), isTrue);
    await lock.release();
    expect(lockFile.existsSync(), isFalse);
    expect(await lock.tryAcquire(), isTrue);
  });

  test('release is safe when not held', () async {
    final lock = SyncLock(lockFile);
    await lock.release(); // no lockfile exists — must not throw
  });

  test('stale lock (crashed holder) is taken over', () async {
    // Simulate a crashed sync: lockfile exists with an old mtime.
    await lockFile.create();
    await lockFile.setLastModified(
      DateTime.now().subtract(const Duration(minutes: 30)),
    );

    final lock = SyncLock(lockFile, staleAfter: const Duration(minutes: 10));
    expect(await lock.tryAcquire(), isTrue);
  });

  test('fresh lock is NOT treated as stale', () async {
    await lockFile.create(); // mtime = now

    final lock = SyncLock(lockFile, staleAfter: const Duration(minutes: 10));
    expect(await lock.tryAcquire(), isFalse);
  });
}
