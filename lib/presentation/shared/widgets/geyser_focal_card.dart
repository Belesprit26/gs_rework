import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'neu/neu.dart';
import 'temperature_display.dart';

/// The main dashboard "hero" card that shows a single geyser's
/// status, temperature reading, and power toggle.
///
/// Entirely stateless and data-driven — the parent provides values
/// and callbacks. No Firebase / BLoC coupling.
class GeyserFocalCard extends StatelessWidget {
  const GeyserFocalCard({
    super.key,
    required this.name,
    required this.isOn,
    required this.temperature,
    required this.onToggle,
    this.isLoading = false,
    this.isBusy = false,
    this.onSensorOfflineTap,
  });

  /// Display name of the geyser (e.g. "Buti").
  final String name;

  /// Whether the geyser is currently powered (relay closed).
  final bool isOn;

  /// Current sensor temperature in °C.  Negative means sensor offline.
  final double temperature;

  /// Whether the initial data is still loading.
  final bool isLoading;

  /// Whether a toggle operation is in progress.
  final bool isBusy;

  /// Called when the user taps the power toggle.
  final VoidCallback onToggle;

  /// Called when the user taps the "?" sensor-offline indicator.
  final VoidCallback? onSensorOfflineTap;

  @override
  Widget build(BuildContext context) {
    return NeuPanel(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      borderRadius: 24,
      color: AppColors.surface,
      glowColor: isOn
          ? _accentForTemp(temperature).withValues(alpha: 0.16)
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Status label ────────────────────────────────────────
          _StatusLabel(name: name, isOn: isOn),
          const SizedBox(height: 16),

          // ── Temperature gauge ───────────────────────────────────
          TemperatureDisplay(
            temperature: temperature,
            isLoading: isLoading,
            size: 170,
            onSensorOfflineTap: onSensorOfflineTap,
          ),
          const SizedBox(height: 20),

          // ── Toggle ─────────────────────────────────────────────
          _PowerToggle(
            isOn: isOn,
            isBusy: isBusy,
            onTap: onToggle,
          ),
        ],
      ),
    );
  }

  /// Returns a colour based on temperature (cool → warm → hot).
  static Color _accentForTemp(double temp) {
    if (temp >= 50) return const Color(0xFFE84855);
    if (temp >= 35) return const Color(0xFFFFA62B);
    return const Color(0xFF5BC0EB);
  }
}

// ── Sub-widgets (private to this file) ──────────────────────────────

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.name, required this.isOn});

  final String name;
  final bool isOn;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOn ? const Color(0xFF4CAF50) : Colors.grey,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          "$name's: ${isOn ? 'On' : 'Off'}",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

class _PowerToggle extends StatelessWidget {
  const _PowerToggle({
    required this.isOn,
    required this.isBusy,
    required this.onTap,
  });

  final bool isOn;
  final bool isBusy;
  final VoidCallback onTap;

  static const _accent = Color(0xFFFFA62B);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isBusy ? null : onTap,
      child: SizedBox(
        width: 64,
        height: 34,
        child: Stack(
          children: [
            // Inset groove track (tints amber when on).
            Positioned.fill(
              child: CustomPaint(
                painter: NeuTrackPainter(
                  isOn: isOn,
                  accent: _accent,
                  base: AppColors.surface,
                ),
              ),
            ),
            // Raised thumb slides in the groove.
            AnimatedAlign(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: isOn ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: NeuRaisedCircle(
                  size: 26,
                  distance: 2,
                  blur: 4,
                  color: AppColors.surface,
                  child: isBusy
                      ? const Padding(
                          padding: EdgeInsets.all(6),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

