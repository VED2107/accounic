import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../motion.dart';

/// A sparkline (context.md §30 — reporting stays out of v1; this is context,
/// not a report).
///
/// One smoothed path and an optional fill, painted directly. No chart package,
/// no axes, no grid, no tooltip: the shape is the whole message and the figure
/// beside it carries the value. It repaints only when the points change, so it
/// costs nothing while the user scrolls.
///
/// Excluded from semantics deliberately — everything it shows is already stated
/// in words next to it, so announcing it again would only add noise.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.points,
    required this.color,
    this.height = 34,
    this.fill = true,
    this.animate = true,
  });

  final List<int> points;
  final Color color;
  final double height;
  final bool fill;

  /// Draws the line on once, left to right, when it first appears. The stroke
  /// arriving in the direction time runs is the one animation on the dashboard
  /// that carries meaning rather than decorating: it says which end is now.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return SizedBox(height: height);

    Widget paint(double progress) => SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(painter: _SparklinePainter(points, color, fill, progress)),
        );

    return ExcludeSemantics(
      child: !animate || Motion.of(context)
          ? paint(1)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: Motion.emphasized,
              curve: Motion.enter,
              builder: (context, value, _) => paint(value),
            ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.points, this.color, this.fill, this.progress);

  final List<int> points;
  final Color color;
  final bool fill;

  /// 0 to 1 — how much of the line has been drawn.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 3.0;
    var min = points.first, max = points.first;
    for (final value in points) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    final span = (max - min) == 0 ? 1 : (max - min);

    Offset at(int index) => Offset(
          index / (points.length - 1) * size.width,
          size.height - pad - (points[index] - min) / span * (size.height - pad * 2),
        );

    // Midpoint quadratics: a straight polyline over thirty points reads as a
    // seismograph rather than a trend.
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      final previous = at(i - 1);
      final current = at(i);
      path.quadraticBezierTo(
        previous.dx,
        previous.dy,
        (previous.dx + current.dx) / 2,
        (previous.dy + current.dy) / 2,
      );
    }
    final last = at(points.length - 1);
    path.lineTo(last.dx, last.dy);

    if (progress <= 0) return;

    // The partial path is taken by arc length rather than by dropping points,
    // so the line grows smoothly instead of stepping between samples.
    final drawn = progress >= 1 ? path : _upTo(path, progress);
    final head = progress >= 1 ? last : _endOf(drawn) ?? last;

    if (fill) {
      final area = Path.from(drawn)
        ..lineTo(head.dx, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.24), color.withValues(alpha: 0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    canvas.drawCircle(head, 2.2, Paint()..color = color);
  }

  static Path _upTo(Path path, double fraction) {
    final result = Path();
    for (final metric in path.computeMetrics()) {
      result.addPath(metric.extractPath(0, metric.length * fraction), Offset.zero);
    }
    return result;
  }

  static Offset? _endOf(Path path) {
    for (final metric in path.computeMetrics().toList().reversed) {
      final tangent = metric.getTangentForOffset(metric.length);
      if (tangent != null) return tangent.position;
    }
    return null;
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color ||
      old.fill != fill ||
      old.progress != progress ||
      !identical(old.points, points);
}

/// "↑ 12.5% vs prior 15 days" — the direction coloured by whether it is good
/// news, which is not the same as whether it went up.
class TrendChip extends StatelessWidget {
  const TrendChip({
    super.key,
    required this.changePercent,
    required this.suffix,
    this.goodWhenUp = true,
  });

  final double? changePercent;
  final String suffix;
  final bool goodWhenUp;

  @override
  Widget build(BuildContext context) {
    final change = changePercent;
    if (change == null) return const SizedBox.shrink();

    final rounded = (change.abs() * 10).round() / 10;
    if (rounded == 0) {
      return Text('No change $suffix',
          style: TextStyle(fontSize: 11, color: context.money.inkFaint));
    }

    final up = change > 0;
    final good = up == goodWhenUp;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${up ? '↑' : '↓'} $rounded%',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: good ? context.money.receivable : context.money.payable,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            suffix,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: context.money.inkFaint),
          ),
        ),
      ],
    );
  }
}
