import 'package:flutter/material.dart';

/// A compact, reusable information row with a leading coloured icon
/// and a text label. Used for geyser stats, settings summaries, etc.
///
/// Replaces the over-engineered `HomerInfoCard` from Orange with a
/// simpler, composable API.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.iconBackgroundColor,
    this.trailing,
    this.onTap,
  });

  /// Icon displayed inside the coloured circle.
  final IconData icon;

  /// Primary label (e.g. "Estimated Daily Saving: R12.50").
  final String title;

  /// Optional second line.
  final String? subtitle;

  /// Icon colour override (defaults to white).
  final Color? iconColor;

  /// Background colour for the icon circle.
  final Color? iconBackgroundColor;

  /// Optional trailing widget (e.g. a chevron or switch).
  final Widget? trailing;

  /// Called when the tile is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = iconBackgroundColor ?? Colors.grey.shade700;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor ?? Colors.white, size: 18),
            ),
            const SizedBox(width: 12),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Trailing
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
