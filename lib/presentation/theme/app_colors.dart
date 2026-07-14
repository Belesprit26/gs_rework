import 'package:flutter/material.dart';

/// Central colour tokens for GeyserSwitch.
///
/// Derived from the logo's temperature arc plus a cool-biased neutral
/// set. This is the single source of truth — widgets reference these
/// (or the [ThemeData] built from them in `app_theme.dart`) instead of
/// hardcoding greys. Structured so a dark variant is a later drop-in.
abstract final class AppColors {
  // ── Neutrals (cool-biased) ──────────────────────────────────────
  /// Page / scaffold background.
  static const paper = Color(0xFFEFF1F4);

  /// Cards, tiles, app bar.
  static const surface = Color(0xFFFFFFFF);

  /// Subtle raised fill (e.g. segmented-control track).
  static const surfaceAlt = Color(0xFFF1F3F6);

  /// 1px borders and dividers — the "subtle but obvious" tile edge.
  static const hairline = Color(0xFFE6EAEE);

  /// Primary text.
  static const ink = Color(0xFF14181C);

  /// Subtitles / secondary text.
  static const inkSecondary = Color(0xFF565E68);

  /// Labels, hints, captions.
  static const muted = Color(0xFF99A1AB);

  // ── Brand: temperature ramp (logo arc, cool → hot) ──────────────
  static const rampPeriwinkle = Color(0xFF6E86C4);
  static const rampBlue = Color(0xFF3E80A0);
  static const rampTeal = Color(0xFF2C8C88);
  static const rampGreen = Color(0xFF6E9E62);
  static const rampAmber = Color(0xFFE3A23B);
  static const rampOrange = Color(0xFFE5701F);
  static const rampRed = Color(0xFFDE3F26);

  /// The full cool→hot ramp (gauge, accents, savings thermometer).
  static const tempRamp = <Color>[
    rampPeriwinkle,
    rampBlue,
    rampTeal,
    rampGreen,
    rampAmber,
    rampOrange,
    rampRed,
  ];

  // ── Accent / semantic ───────────────────────────────────────────
  /// Primary accent — the arc's teal ("efficiency" side).
  static const primary = rampTeal;

  /// Positive / savings.
  static const save = Color(0xFF2E9E6B);

  /// Spend / the "usual bill" side of the savings thermometer.
  static const spend = rampOrange;

  static const warning = rampAmber;
  static const critical = rampRed;

  // ── Neomorphic surface (focal card only) ────────────────────────
  //
  // Scoped to the dashboard focal card. These are *additive* — the rest
  // of the app keeps `surface`/`paper`, so nothing else re-renders.
  // Depth is created by a light highlight (top-left) + dark shadow
  // (bottom-right) pair over a shared mid-light base tone. Structured
  // as tokens so a dark variant is a later drop-in.

  /// Shared base tone for extruded/inset neomorphic elements. Slightly
  /// darker than `paper` so both the highlight and shadow have room.
  static const neuBase = Color(0xFFE8EBF0);

  /// Top-left light source (raised highlight / inset floor).
  static const neuHighlight = Color(0xFFFFFFFF);

  /// Bottom-right cast shadow (raised shadow / inset wall).
  static const neuShadow = Color(0xFFC5CBD6);
}
