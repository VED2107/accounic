import 'package:flutter/material.dart';

import '../../core/theme.dart';
import 'splash_timeline.dart';

/// The Accounic mark, assembling itself (context.md §18).
///
/// The geometry is `brand/accounic-icon.svg`, coordinate for coordinate, on the
/// same 512 grid — the ribbon "A", three ascending bars, and the growth arrow
/// curving up through them. Nothing is re-proportioned or re-drawn; the only
/// thing added is time.
///
/// It is one [CustomPainter] rather than a widget per element. Three animated
/// widgets stacked with `Transform`s and `ClipRect`s would each force layout and
/// a saveLayer every frame; one painter reading four values off one animation
/// draws the whole mark in a handful of path operations, inside a
/// [RepaintBoundary], with no layout at all. On a mid-range Android device that
/// is the difference between the sequence holding 60fps and not.
class AccounicLogoAnimation extends StatelessWidget {
  const AccounicLogoAnimation({
    super.key,
    required this.animation,
    required this.size,
    required this.reducedMotion,
  });

  final Animation<double> animation;
  final double size;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: animation,
          builder:
              (context, _) => CustomPaint(
                painter: _MarkPainter(t: animation.value, reducedMotion: reducedMotion),
              ),
        ),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.t, required this.reducedMotion});

  final double t;
  final bool reducedMotion;

  /// The SVG's grid. Every literal below is a coordinate from
  /// `brand/accounic-icon.svg`.
  static const _grid = 512.0;

  static const _bars = [
    (x: 178.0, y: 362.0, height: 52.0, color: Color(0xFF2563EB)),
    (x: 228.0, y: 322.0, height: 92.0, color: Color(0xFF06B6D4)),
    (x: 278.0, y: 278.0, height: 136.0, color: Color(0xFF22C55E)),
  ];

  /// The arrow's ink. The SVG uses a near-black navy so the arrow reads *inside*
  /// the bright ribbon; on the splash's dark ground that would disappear, so it
  /// is lightened to the same cool white the wordmark uses. Same shape, legible
  /// ground — the one deviation from the asset, and it is a contrast fix rather
  /// than a redesign.
  static const _arrowInk = Color(0xFFE8EEF9);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / _grid;

    if (reducedMotion) {
      _paintRibbon(canvas, size, k, 1);
      for (final bar in _bars) {
        _paintBar(canvas, k, bar, 1);
      }
      _paintArrow(canvas, k, 1, 1);
      return;
    }

    final enter = SplashTimeline.markEnter.transform(t);
    final settle = SplashTimeline.settle.transform(t);

    // Entrance and settle are one transform, not two stacked ones: the mark
    // scales 0.82 → 1 as it draws, then 0.985 → 1 as it settles, and applying
    // them together avoids a second matrix and a second repaint region.
    final scale = lerpDouble(0.82, 1, enter) * lerpDouble(0.985, 1, settle);
    final lift = lerpDouble(12 * k, 0, enter);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2 + lift);
    canvas.scale(scale);
    canvas.translate(-size.width / 2, -size.height / 2);

    _paintRibbon(canvas, size, k, SplashTimeline.markDraw.transform(t));

    for (final (index, bar) in _bars.indexed) {
      _paintBar(canvas, k, bar, SplashTimeline.bars[index].transform(t));
    }

    _paintArrow(
      canvas,
      k,
      SplashTimeline.arrowDraw.transform(t),
      SplashTimeline.arrowHead.transform(t),
    );

    canvas.restore();
  }

  /// The "A": a gradient ribbon drawn from its left foot, up to the apex, and
  /// down to its right foot — the direction a hand would draw it.
  void _paintRibbon(Canvas canvas, Size size, double k, double progress) {
    if (progress <= 0) return;

    final path =
        Path()
          ..moveTo(96 * k, 414 * k)
          ..lineTo(256 * k, 104 * k)
          ..lineTo(416 * k, 414 * k);

    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 58 * k
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..shader = AccounicColors.brandGradient.createShader(
            Rect.fromLTWH(0, 0, size.width, size.height),
          );

    canvas.drawPath(progress >= 1 ? path : _partial(path, progress), paint);
  }

  /// A bar, growing from its own baseline rather than from the canvas floor —
  /// which is what makes three bars of different heights finish together
  /// instead of appearing to slide up past each other.
  void _paintBar(
    Canvas canvas,
    double k,
    ({double x, double y, double height, Color color}) bar,
    double progress,
  ) {
    if (progress <= 0) return;

    final baseline = (bar.y + bar.height) * k;
    final height = bar.height * k * progress;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(bar.x * k, baseline - height, 36 * k, height),
        Radius.circular(9 * k),
      ),
      Paint()..color = bar.color,
    );
  }

  /// The growth arrow: a curve that leaves the first bar, rises through the
  /// chart and finishes pointing up and to the right. Drawn along its own arc
  /// length, so the stroke *travels* rather than fading in — and the head is
  /// scaled in from nothing at the very end, once the stroke has arrived to
  /// meet it.
  void _paintArrow(Canvas canvas, double k, double draw, double head) {
    if (draw > 0) {
      final path =
          Path()
            ..moveTo(172 * k, 356 * k)
            ..quadraticBezierTo(250 * k, 350 * k, 300 * k, 268 * k);

      canvas.drawPath(
        draw >= 1 ? path : _partial(path, draw),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 15 * k
          ..strokeCap = StrokeCap.round
          ..color = _arrowInk,
      );
    }

    if (head <= 0) return;

    // The head grows about its own tip, so it opens out of the stroke's end
    // rather than popping in beside it.
    const tip = Offset(325, 244);
    canvas.save();
    canvas.translate(tip.dx * k, tip.dy * k);
    canvas.scale(head);
    canvas.translate(-tip.dx * k, -tip.dy * k);
    canvas.drawPath(
      Path()
        ..moveTo(325 * k, 244 * k)
        ..lineTo(309 * k, 279 * k)
        ..lineTo(290 * k, 254 * k)
        ..close(),
      Paint()..color = _arrowInk,
    );
    canvas.restore();
  }

  /// The first [fraction] of a path, measured by arc length.
  static Path _partial(Path path, double fraction) {
    final result = Path();
    for (final metric in path.computeMetrics()) {
      result.addPath(metric.extractPath(0, metric.length * fraction), Offset.zero);
    }
    return result;
  }

  static double lerpDouble(double a, double b, double t) => a + (b - a) * t;

  @override
  bool shouldRepaint(_MarkPainter old) => old.t != t || old.reducedMotion != reducedMotion;
}
