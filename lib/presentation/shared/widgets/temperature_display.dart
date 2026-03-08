import 'package:flutter/material.dart';

/// A circular temperature gauge that shows the current reading
/// inside a gradient ring.
///
/// Designed to be data-driven: pass [temperature], and it renders.
/// No Firebase coupling — the parent is responsible for streaming data.
class TemperatureDisplay extends StatelessWidget {
  const TemperatureDisplay({
    super.key,
    required this.temperature,
    this.unit = 'Celsius',
    this.isLoading = false,
    this.size = 180,
    this.onTap,
  });

  /// Current temperature value.
  final double temperature;

  /// Unit label displayed below the reading.
  final String unit;

  /// Shows a spinner instead of the reading.
  final bool isLoading;

  /// Diameter of the outer ring.
  final double size;

  /// Called when the user taps the display (e.g. to open settings).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final innerSize = size * 0.86;
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(
            temperature: temperature,
            ringWidth: 6,
          ),
          child: Center(
            child: Container(
              width: innerSize,
              height: innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.surfaceContainerLowest,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Center(
                child: isLoading
                    ? SizedBox(
                        width: size * 0.2,
                        height: size * 0.2,
                        child: const CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${temperature.round()}°',
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: size * 0.22,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            unit,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                              fontSize: size * 0.09,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints a gradient arc ring around the temperature circle.
///
/// The arc sweep is proportional to [temperature] / 75 (max expected temp).
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.temperature,
    this.ringWidth = 6,
  });

  final double temperature;
  final double ringWidth;

  static const double _maxTemp = 70;
  static const double _startAngle = 2.35; // ~135°
  static const double _fullSweep = 3.45; // ~260°

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      ringWidth / 2,
      ringWidth / 2,
      size.width - ringWidth,
      size.height - ringWidth,
    );

    // Track background
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round
      ..color = Colors.grey.shade200;

    canvas.drawArc(rect, _startAngle, _fullSweep, false, trackPaint);

    // Value arc
    final fraction = (temperature.clamp(0, _maxTemp) / _maxTemp);
    final sweep = _fullSweep * fraction;

    if (sweep <= 0) return;

    final gradient = SweepGradient(
      startAngle: _startAngle,
      endAngle: _startAngle + _fullSweep,
      colors: const [
        Color(0xFF5BC0EB), // cool blue
        Color(0xFFFFA62B), // warm orange
        Color(0xFFE84855), // hot red
      ],
      stops: const [0.0, 0.55, 1.0],
    );

    final valuePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round
      ..shader = gradient.createShader(rect);

    canvas.drawArc(rect, _startAngle, sweep, false, valuePaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.temperature != temperature;
}
