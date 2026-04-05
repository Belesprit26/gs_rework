import '../entities/daily_stats.dart';
import '../entities/geyser_live.dart';
import '../entities/geyser_settings.dart';

/// Domain contract for Firebase RTDB operations.
///
/// Paths: gs/{uid}/live/{did}, gs/{uid}/set/{did}, gs/{uid}/stats/{did}/{date}
abstract class RtdbRepository {
  /// Stream live telemetry for a device.
  Stream<GeyserLive> watchLive(String deviceId);

  /// Stream current settings for a device.
  Stream<GeyserSettings> watchSettings(String deviceId);

  /// One-shot read of current settings from `set/{did}`.
  Future<GeyserSettings> readSettings(String deviceId);

  /// Write settings (partial or full) to the command node.
  Future<void> writeSettings(String deviceId, Map<String, dynamic> fields);

  /// Toggle the relay via the command node and wait up to [timeout]
  /// for the live node to confirm.  Returns true if confirmed.
  Future<bool> toggleRelay(
    String deviceId,
    bool desiredState, {
    Duration timeout = const Duration(seconds: 2),
  });

  /// Stream today's aggregated stats for a device.
  Stream<DailyStats> watchTodayStats(String deviceId);

  /// Write "last app open" timestamp to meta/app.
  Future<void> touchAppActive();

  /// Read last boot time for a device (epoch seconds from firmware).
  Future<DateTime?> getLastBoot(String deviceId);
}
