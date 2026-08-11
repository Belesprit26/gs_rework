import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../feedback/haptics.dart';

/// Whole-hour run-limit presets, shared by the Settings tab and the
/// temperature dialog. Firmware ≥ 0.7.0 suppresses a timer that would
/// fire within 60 s of a run-limit cutoff, so a duration equal to the
/// gap between two timers is safe — the earlier ":58" values that dodged
/// that collision by hand are retired.
const runLimitPresets = <({String label, int minutes})>[
  (label: 'Off', minutes: 0),
  (label: '1 hour', minutes: 60),
  (label: '2 hours', minutes: 120),
  (label: '4 hours', minutes: 240),
  (label: '6 hours', minutes: 360),
  (label: '8 hours', minutes: 480),
];

/// About one full heat-up for an average geyser — the value the chips
/// nudge toward with a star.
const runLimitRecommendedMinutes = 120;

/// A wrap of duration chips for the max-continuous-run limit.
///
/// Deliberately dumb and *controlled*: it renders [currentMinutes] as the
/// selected chip and calls [onSelect] when one is tapped. The caller
/// decides what that does — write immediately (Settings) or stage the
/// choice until a Save button (the temperature dialog) — so the same
/// control is honest under both a live list and a Cancel/Save dialog.
class RunLimitChips extends StatelessWidget {
  const RunLimitChips({
    super.key,
    required this.currentMinutes,
    required this.onSelect,
  });

  final int currentMinutes;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: runLimitPresets.map((p) {
        return RunLimitChip(
          label: p.label,
          selected: p.minutes == currentMinutes,
          recommended: p.minutes == runLimitRecommendedMinutes,
          onTap: () {
            // Detent only when the selection actually changes.
            if (p.minutes != currentMinutes) Haptics.select();
            onSelect(p.minutes);
          },
        );
      }).toList(),
    );
  }
}

/// A flat run-limit chip: teal fill when selected, hairline outline when
/// not. Deliberately flat (not the neomorphic timer-chip treatment) — it
/// sits on a white list card or a dialog surface, which carries the
/// depth. A small star marks the recommended option while it is
/// unselected.
class RunLimitChip extends StatelessWidget {
  const RunLimitChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.recommended = false,
  });

  final String label;
  final bool selected;
  final bool recommended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.hairline,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (recommended && !selected) ...[
                const Icon(Icons.star_rounded,
                    size: 13, color: AppColors.primary),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.inkSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
