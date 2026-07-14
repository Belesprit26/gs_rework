import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import 'neu.dart';

/// Neomorphic slider styling: an inset (grooved) track with the active
/// portion tinted [accent], and a raised circular thumb.
///
/// Wrap a standard [Slider] in `SliderTheme(data: neuSliderTheme(...))` so
/// all of Slider's gesture logic, divisions and semantics are preserved —
/// only the paint changes.
SliderThemeData neuSliderTheme(BuildContext context, {required Color accent}) {
  return SliderTheme.of(context).copyWith(
    trackHeight: 8,
    trackShape: NeuSliderTrackShape(accent: accent),
    thumbShape: const NeuSliderThumbShape(),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    // Divisions still snap; the dots just muddied the coloured fill.
    tickMarkShape: SliderTickMarkShape.noTickMark,
    activeTrackColor: accent,
    inactiveTrackColor: AppColors.neuBase,
    thumbColor: AppColors.neuBase,
    overlayColor: accent.withValues(alpha: 0.12),
  );
}

/// Inset groove track. Floor is the base tone with an inner shadow; the
/// active side (left of the thumb) is filled with the accent.
class NeuSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const NeuSliderTrackShape({required this.accent});

  final Color accent;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final canvas = context.canvas;
    final radius = Radius.circular(trackRect.height / 2);
    final rrect = RRect.fromRectAndRadius(trackRect, radius);

    // Groove floor + carved walls.
    canvas.drawRRect(rrect, Paint()..color = AppColors.neuBase);
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

    // Active fill (clipped to the groove).
    final isLtr = textDirection == TextDirection.ltr;
    final activeRect = isLtr
        ? Rect.fromLTRB(
            trackRect.left, trackRect.top, thumbCenter.dx, trackRect.bottom)
        : Rect.fromLTRB(
            thumbCenter.dx, trackRect.top, trackRect.right, trackRect.bottom);
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, radius),
      Paint()..color = accent,
    );
    canvas.restore();
  }
}

/// Raised circular thumb (dual soft shadows around a base disc).
class NeuSliderThumbShape extends SliderComponentShape {
  const NeuSliderThumbShape({this.radius = 12});

  final double radius;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      Size.fromRadius(radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center + const Offset(2, 2),
      radius,
      Paint()
        ..color = AppColors.neuShadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      center + const Offset(-2, -2),
      radius,
      Paint()
        ..color = AppColors.neuHighlight
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, radius, Paint()..color = AppColors.neuBase);
  }
}
