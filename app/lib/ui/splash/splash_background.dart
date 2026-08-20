import 'package:flutter/material.dart';

/// The room the logo is lit in (context.md §18).
///
/// A deep navy ground with two very weak radial lights: a blue-cyan one behind
/// the mark, and a green one low and to the right, which is where the brand
/// ramp ends. Neither is bright enough to read as a "glow" — they exist so the
/// ground is not a flat rectangle of one colour, which is what makes a dark
/// splash look cheap.
///
/// Banding is the real risk at this scale. A gradient spread over 900 vertical
/// pixels between two nearly identical dark colours quantises into visible
/// steps on an 8-bit display, so the radii here are deliberately wide, the
/// stops are few, and the two lights are painted as separate low-alpha layers
/// rather than as one many-stop gradient — overlapping soft alpha dithers the
/// steps away far better than adding stops does.
class SplashBackground extends StatelessWidget {
  const SplashBackground({super.key, required this.opacity});

  /// How far up the ambient light has come. The navy ground is painted at full
  /// strength from the very first frame — it has to match the native launch
  /// colour exactly — and only the lights fade in.
  final double opacity;

  /// The ground. Identical to the Android launch drawable and the Windows
  /// window brush, so the handover from the native launch surface to Flutter's
  /// first frame is invisible.
  static const ground = Color(0xFF070A12);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _BackgroundPainter(opacity), size: Size.infinite),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter(this.opacity);

  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = SplashBackground.ground);

    if (opacity <= 0) return;

    // Sized off the diagonal so the composition holds at 16:9, at ultrawide and
    // at a phone's 9:19.5 without the lights either vanishing or swamping it.
    final diagonal = size.longestSide;

    void light(Offset centre, double radius, Color color, double alpha) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: alpha * opacity), color.withValues(alpha: 0)],
            stops: const [0, 1],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    // Behind the mark: the blue-cyan end of the ramp.
    light(
      Offset(size.width * 0.5, size.height * 0.42),
      diagonal * 0.44,
      const Color(0xFF2563EB),
      0.16,
    );

    // Low and right: the green end, weaker still, so the ground carries a hint
    // of where the gradient is going without anyone noticing a second light.
    light(
      Offset(size.width * 0.78, size.height * 0.86),
      diagonal * 0.38,
      const Color(0xFF14B8A6),
      0.09,
    );
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.opacity != opacity;
}
