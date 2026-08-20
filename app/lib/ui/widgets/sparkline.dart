import 'package:flutter/material.dart';

import '../../core/theme.dart';

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
  });

  final List<int> points;
  final Color color;
  final double height;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return SizedBox(height: height);
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(painter: _SparklinePainter(points, color, fill)),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter(this.points, this.color, this.fill);

  final List<int> points;
  final Color color;
  final bool fill;

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

    if (fill) {
      final area = Path.from(path)
        ..lineTo(size.width, size.height)
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
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );

    canvas.drawCircle(last, 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || old.fill != fill || !identical(old.points, points);
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
