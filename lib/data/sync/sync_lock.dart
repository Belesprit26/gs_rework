import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/debug/debug_log.dart';

/// Cross-isolate mutual exclusion for the telemetry sync.
///
/// Sync can be triggered from two places that don't share memory:
/// the main isolate (connectivity retry, startup retry check) and the
/// workmanager background isolate (midnight task + backoff retries).
/// An in-memory mutex can't cover both, and `RandomAccessFile.lock()`
/// (fcntl) is process-scoped — two isolates in the same process would
/// both acquire it. Atomic exclusive file creation (O_EXCL) works
/// across isolates *and* processes.
///
/// This lock makes concurrent syncs **rare**, not impossible: a crash
/// leaves a stale lockfile which is taken over after [staleAfter], and
/// the takeover has a small inherent race. That is acceptable because
/// the chunked upload design makes a concurrent sync **harmless**
/// (worst case: a duplicate chunk object, never data loss).
class SyncLock {
  SyncLock(this._lockFile, {this.staleAfter = const Duration(minutes: 10)});

  /// Lock file co-located with the app database, so both isolates
  /// resolve the same path with the same mechanism.
  static Future<SyncLock> inDocumentsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    return SyncLock(File(p.join(dir.path, 'telemetry_sync.lock')));
  }

  final File _lockFile;
  final Duration staleAfter;

  /// Try to acquire the lock. Returns false if another sync holds it.
  Future<bool> tryAcquire() async {
    if (await _tryCreate()) return true;

    // Lock exists — held by a live sync, or left by a crashed one.
    if (!await _isStale()) return false;

    debugLog('SyncLock', 'Stale lock (>${staleAfter.inMinutes}m) — taking over');
    try {
      await _lockFile.delete();
    } on FileSystemException {
      // Someone else deleted it first — fall through to one retry.
    }
    return _tryCreate();
  }

  /// Release the lock. Safe to call even if not held.
  Future<void> release() async {
    try {
      await _lockFile.delete();
    } on FileSystemException {
      // Already gone — nothing to do.
    }
  }

  // ── Private ───────────────────────────────────────────────────────

  Future<bool> _tryCreate() async {
    try {
      await _lockFile.create(exclusive: true);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  Future<bool> _isStale() async {
    try {
      final modified = (await _lockFile.stat()).modified;
      return DateTime.now().difference(modified) > staleAfter;
    } on FileSystemException {
      // Disappeared between create-fail and stat — treat as stale so
      // the caller retries the create once.
      return true;
    }
  }
}
