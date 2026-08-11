import 'package:flutter/services.dart';

/// The app's haptic vocabulary — five semantic verbs over Flutter's
/// built-in [HapticFeedback] (no plugin, no permissions; both platforms
/// respect the system haptic setting and silently no-op without an
/// engine, e.g. iPads).
///
/// Widgets call the *verb*, never a raw impact, so the feel stays
/// consistent and a future user "haptics off" preference has a single
/// choke point. `HapticFeedback.vibrate()` is deliberately absent — the
/// long buzzer reads as an alarm.
///
/// Ground rule (UX_POLISH_PLAN §B): haptics fire only on user-initiated
/// actions or milestones of a flow the user is actively watching.
/// Background events (auto-reconnects, FCM arrivals) never buzz.
abstract final class Haptics {
  /// Picked one option among several — chips, segments, switches, tabs.
  /// The lightest click, like a detent. Fire on *change*, not re-taps.
  static void select() => HapticFeedback.selectionClick();

  /// Soft acknowledgment of a minor tap — badges, the app-bar logo,
  /// quiet progress ticks.
  static void tap() => HapticFeedback.lightImpact();

  /// A state-changing action was sent — the power toggle, a Save.
  static void commit() => HapticFeedback.mediumImpact();

  /// The double-tick of a job confirmed done — save landed, device
  /// connected, provisioning complete.
  static Future<void> success() async {
    HapticFeedback.mediumImpact();
    await Future<void>.delayed(const Duration(milliseconds: 90));
    HapticFeedback.lightImpact();
  }

  /// A thud — the action was refused (leak-gated toggle) or a watched
  /// flow failed. Pair with a warning/error snack.
  static void blocked() => HapticFeedback.heavyImpact();
}
