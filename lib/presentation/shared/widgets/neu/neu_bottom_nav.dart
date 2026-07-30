import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import 'neu.dart';

/// A single destination in [NeuBottomNav].
class NeuNavItem {
  const NeuNavItem({
    required this.icon,
    required this.label,
    this.selectedIcon,
  });

  final IconData icon;

  /// Optional filled variant shown when the item is selected.
  final IconData? selectedIcon;

  final String label;
}

/// A neomorphic bottom navigation bar (Design 2 — "grooved active well").
///
/// A flat white bar; the selected destination sits inside a debossed
/// [NeuInset] groove with the [accent] colour, matching the groove
/// language used by the gauge ring, sliders and timer chips. Fully
/// custom-drawn, so it renders identically on Android and iOS.
class NeuBottomNav extends StatelessWidget {
  const NeuBottomNav({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.accent = AppColors.primary,
  });

  final List<NeuNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          // Soft upward lift to separate the bar from scrolling content.
          BoxShadow(
            color: Color(0x14141C24),
            blurRadius: 16,
            offset: Offset(0, -4),
            spreadRadius: -4,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTab(
                    item: items[i],
                    selected: i == selectedIndex,
                    accent: accent,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final NeuNavItem item;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? accent : AppColors.muted;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selected ? (item.selectedIcon ?? item.icon) : item.icon,
          size: 24,
          color: color,
        ),
        const SizedBox(height: 4),
        Text(
          item.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ],
    );

    // heightFactor: 1.0 makes this hug the child's height instead of
    // expanding to fill the (loose, up-to-full-screen) vertical space the
    // Scaffold hands the bottom bar — otherwise the bar grows to fill the
    // screen. widthFactor is left null so the tap target still fills the
    // Expanded slot and the child stays horizontally centred.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1.0,
        child: selected
            ? NeuInset(
                borderRadius: 18,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: content,
              )
            : Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: content,
              ),
      ),
    );
  }
}
