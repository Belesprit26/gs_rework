import '../entities/geyser_snapshot.dart';

/// Domain contract for controlling a geyser via BLE.
///
/// This layer translates between domain types and raw BLE bytes.
/// The UI only talks to this interface — never directly to BLE.
abstract class GeyserControlRepository {
  // ── Read ──────────────────────────────────────────────────────────

  /// Read the full current state of the geyser (one-shot).
  /// This performs individual BLE reads on each characteristic.
  Future<GeyserSnapshot> readSnapshot();

  /// The most recent snapshot, updated by [readSnapshot] and
  /// notification streams.  Returns a default snapshot if no data
  /// has been read yet.
  GeyserSnapshot get lastSnapshot;

  // ── Streams ───────────────────────────────────────────────────────

  /// Subscribe to real-time temperature updates.
  /// The stream emits the latest temperature in °C.
  Stream<double> get temperatureStream;

  /// Subscribe to geyser on/off state changes.
  Stream<bool> get geyserStateStream;

  // ── Write commands ────────────────────────────────────────────────

  /// Turn the geyser on or off.
  Future<void> setGeyserState(bool on);

  /// Set the min and max temperature limits, plus auto-reheat flag.
  Future<void> setTempLimits({
    required int min,
    required int max,
    required bool autoReheat,
  });

  /// Write the full timer configuration.
  Future<void> setTimers(List<GeyserTimer> timers);

  /// Push the phone's current Unix timestamp to the device.
  /// Called once per BLE connection cycle for time synchronisation.
  Future<void> pushPhoneTime();

  // ── Lifecycle ─────────────────────────────────────────────────────

  /// Start listening for notifications (call after BLE is ready).
  Future<void> startListening();

  /// Stop listening and clean up subscriptions.
  Future<void> stopListening();

  /// Release all resources. Call when the repository is no longer needed.
  Future<void> dispose();
}
