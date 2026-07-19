import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// Neomorphic ("soft UI") primitives, scoped to the dashboard focal card.
///
/// Depth is created by a light highlight (top-left) + dark shadow
/// (bottom-right) pair over the shared [AppColors.neuBase] tone:
///   • raised   → shadows *outside* the shape ([neuRaisedShadows]).
///   • inset    → shadows *inside* the shape ([drawInnerShadow]).
///
/// Flutter's [BoxShadow] has no `inset` mode, so grooves are painted in a
/// [CustomPainter] via [drawInnerShadow]. Everything here is self-contained
/// (no packages) so it stays auditable and dark-mode-ready.

/// Dual drop-shadow pair for a raised element.
List<BoxShadow> neuRaisedShadows({double distance = 5, double blur = 12}) {
  return [
    BoxShadow(
      color: AppColors.neuShadow,
      offset: Offset(distance, distance),
      blurRadius: blur,
    ),
    BoxShadow(
      color: AppColors.neuHighlight,
      offset: Offset(-distance, -distance),
      blurRadius: blur,
    ),
  ];
}

/// Paints a soft inner shadow inside [shape], clipped to it.
///
/// Draws the *negative* of [shape] (everything outside it), shifted by
/// [offset] and blurred, clipped to the inside — the classic inset trick.
/// Call twice (dark down-right, light up-left) for a carved groove.
void drawInnerShadow(
  Canvas canvas,
  Path shape, {
  required Color color,
  required Offset offset,
  required double blur,
}) {
  canvas.save();
  canvas.clipPath(shape);
  final bounds =
      shape.getBounds().inflate(blur * 3 + offset.distance.abs() * 2 + 24);
  final negative = Path.combine(
    PathOperation.difference,
    Path()..addRect(bounds),
    shape,
  );
  final paint = Paint()
    ..color = color
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
  canvas.drawPath(negative.shift(offset), paint);
  canvas.restore();
}

/// A raised rounded-rectangle panel. Replaces bordered cards.
class NeuPanel extends StatelessWidget {
  const NeuPanel({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 24,
    this.color,
    this.glowColor,
    this.distance = 6,
    this.blur = 16,
    this.width = double.infinity,
  });

  final Widget child;
  final double? width;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? color;

  /// Optional coloured halo (e.g. the ON accent) layered on the neutral
  /// shadows — keeps state signalling without a hard border.
  final Color? glowColor;
  final double distance;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.neuBase,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          ...neuRaisedShadows(distance: distance, blur: blur),
          if (glowColor != null)
            BoxShadow(
              color: glowColor!,
              blurRadius: blur + 8,
              spreadRadius: 1,
            ),
        ],
      ),
      child: child,
    );
  }
}

/// Paints a pill-shaped track as an inset (debossed) groove.
///
/// Shared by the power toggle and [NeuSwitch]. Tints toward [accent] when
/// [isOn]; otherwise the plain base tone.
class NeuTrackPainter extends CustomPainter {
  NeuTrackPainter({
    required this.isOn,
    required this.accent,
    this.base = AppColors.neuBase,
  });

  final bool isOn;
  final Color accent;

  /// Surface tone the groove floor is carved into (white for the focal
  /// card's toggle, [AppColors.neuBase] for the dialog switches).
  final Color base;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.height / 2),
    );

    // Groove floor + carved walls first (on the plain base tone).
    canvas.drawRRect(rrect, Paint()..color = base);
    final path = Path()..addRRect(rrect);
    drawInnerShadow(
      canvas,
      path,
      color: AppColors.neuShadow,
      offset: const Offset(2, 2),
      blur: 3,
    );
    drawInnerShadow(
      canvas,
      path,
      color: AppColors.neuHighlight,
      offset: const Offset(-2, -2),
      blur: 3,
    );

    // When on, lay a crisp full-opacity accent bar *inside* the groove so
    // the colour stays vivid (walls remain visible around it, no blur on
    // top of the colour).
    if (isOn) {
      final innerRect = (Offset.zero & size).deflate(1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          innerRect,
          Radius.circular(innerRect.height / 2),
        ),
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NeuTrackPainter oldDelegate) =>
      oldDelegate.isOn != isOn ||
      oldDelegate.accent != accent ||
      oldDelegate.base != base;
}

/// A neomorphic on/off switch: inset groove track + raised sliding thumb.
///
/// Drop-in replacement for Material [Switch] in the focal-card family.
/// A null [onChanged] renders as disabled.
class NeuSwitch extends StatelessWidget {
  const NeuSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.accent = AppColors.primary,
    this.width = 52,
    this.height = 30,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color accent;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final thumbSize = height - 6;
    return Opacity(
      opacity: enabled ? 1 : 0.3,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: NeuTrackPainter(isOn: value, accent: accent),
                ),
              ),
              AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: NeuRaisedCircle(
                    size: thumbSize,
                    distance: 1,
                    blur: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A neomorphic button. Raised pill; [primary] fills with the accent.
class NeuButton extends StatelessWidget {
  const NeuButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppColors.primary : AppColors.neuBase;
    final fg = primary ? Colors.white : AppColors.inkSecondary;
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          boxShadow: neuRaisedShadows(distance: 3, blur: 7),
        ),
        child: Text(
          label,
          style: TextStyle(color: fg, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// A debossed (inset) pill/chip — the counterpart to [NeuRaisedCircle] for
/// small labels like the preset timer times.
class NeuInset extends StatelessWidget {
  const NeuInset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.borderRadius = 10,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  /// Optional accent wash inside the groove.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _NeuInsetPainter(borderRadius: borderRadius, tint: tint),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _NeuInsetPainter extends CustomPainter {
  _NeuInsetPainter({required this.borderRadius, this.tint});

  final double borderRadius;
  final Color? tint;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = tint != null
            ? Color.alphaBlend(tint!.withValues(alpha: 0.5), AppColors.neuBase)
            : AppColors.neuBase,
    );
    final path = Path()..addRRect(rrect);
    drawInnerShadow(
      canvas,
      path,
      color: AppColors.neuShadow,
      offset: const Offset(1.5, 1.5),
      blur: 2.5,
    );
    drawInnerShadow(
      canvas,
      path,
      color: AppColors.neuHighlight,
      offset: const Offset(-1.5, -1.5),
      blur: 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _NeuInsetPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius || oldDelegate.tint != tint;
}

/// A smooth, borderless white card with a pillowy neomorphic lift — a
/// bright highlight (top-left) + soft shadow (bottom-right) around a white
/// surface. The "Direction B" treatment for the savings card and glance
/// tiles. Keeps the surface white; only the depth cue changes.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 18,
    this.color,
    this.distance = 6,
    this.blur = 16,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final Color? color;
  final double distance;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: neuRaisedShadows(distance: distance, blur: blur),
      ),
      child: child,
    );
  }
}

/// A raised circle. Used for the temperature puck and toggle thumb.
class NeuRaisedCircle extends StatelessWidget {
  const NeuRaisedCircle({
    super.key,
    required this.size,
    this.child,
    this.color,
    this.distance = 4,
    this.blur = 10,
  });

  final double size;
  final Widget? child;
  final Color? color;
  final double distance;
  final double blur;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color ?? AppColors.neuBase,
        boxShadow: neuRaisedShadows(distance: distance, blur: blur),
      ),
      child: child,
    );
  }
}
