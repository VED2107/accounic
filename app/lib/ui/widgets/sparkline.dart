import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/money.dart';
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
    this.zeroBaseline = false,
  });

  final List<int> points;
  final Color color;
  final double height;
  final bool fill;

  /// Force 0 into the vertical domain and draw a hairline through it.
  ///
  /// For any series that can go negative — a net position, a person's balance —
  /// this is the difference between a shape and a statement: a line that rises
  /// is otherwise indistinguishable from one that rises THROUGH zero, which on
  /// a ledger is the only event it is really about. The twin of the web
  /// client's `zeroBaseline`.
  final bool zeroBaseline;

  /// Draws the line on once, left to right, when it first appears. The stroke
  /// arriving in the direction time runs is the one animation on the dashboard
  /// that carries meaning rather than decorating: it says which end is now.
  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return SizedBox(height: height);

    final line = context.money.lineStrong;
    Widget paint(double progress) => SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparklinePainter(points, color, fill, progress, zeroBaseline, line),
          ),
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
  const _SparklinePainter(
    this.points,
    this.color,
    this.fill,
    this.progress,
    this.zeroBaseline,
    this.baselineColor,
  );

  final List<int> points;
  final Color color;
  final bool fill;
  final bool zeroBaseline;
  final Color baselineColor;

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
    // With a baseline, zero is always in frame — so a series that sits entirely
    // on one side of it is not stretched to fill the box, which is what made a
    // small wobble look like a collapse.
    if (zeroBaseline) {
      if (min > 0) min = 0;
      if (max < 0) max = 0;
    }
    final span = (max - min) == 0 ? 1 : (max - min);

    double yFor(num value) =>
        size.height - pad - (value - min) / span * (size.height - pad * 2);

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

    // Only worth drawing when zero is genuinely inside the plotted band: a rule
    // pinned to the very edge of the box is a border, not a baseline.
    final zeroY = yFor(0);
    final showZero = zeroBaseline && zeroY > pad + 0.5 && zeroY < size.height - pad - 0.5;
    if (showZero) {
      // Dashed by hand — Flutter's Canvas has no dash support, and a solid rule
      // here would read as an axis the chart does not have.
      final dash = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = baselineColor;
      for (var x = 0.0; x < size.width; x += 6) {
        canvas.drawLine(Offset(x, zeroY), Offset(x + 3, zeroY), dash);
      }
    }

    // The partial path is taken by arc length rather than by dropping points,
    // so the line grows smoothly instead of stepping between samples.
    final drawn = progress >= 1 ? path : _upTo(path, progress);
    final head = progress >= 1 ? last : _endOf(drawn) ?? last;

    if (fill) {
      // The area fills to the baseline when there is one, so the shaded region
      // means "distance from settled" rather than "distance from the bottom of
      // the box".
      final floor = showZero ? zeroY : size.height;
      final area = Path.from(drawn)
        ..lineTo(head.dx, floor)
        ..lineTo(0, floor)
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

    // The endpoint is the current value, so it is marked rather than merely
    // ended: a ring in the surface colour reads as a pin on the line instead of
    // a thickening of it.
    canvas.drawCircle(head, 3.2, Paint()..color = baselineColor.withValues(alpha: 0));
    canvas.drawCircle(
      head,
      3,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = color,
    );
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
      old.zeroBaseline != zeroBaseline ||
      old.baselineColor != baselineColor ||
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

/// A sparkline that says what it is showing.
///
/// The chart, the range it is drawn against, and the value the line ends on —
/// the three things that turn a decorative stroke into a figure a reader can
/// act on. The Flutter half of the web client's `SparklineFigure`, and it
/// exists for the same reason: the dashboard's line had no baseline, no scale
/// and no ending value, so it could be read as anything.
class SparklineFigure extends StatelessWidget {
  const SparklineFigure({
    super.key,
    required this.points,
    required this.color,
    required this.currency,
    required this.caption,
    this.label,
    this.height = 46,
  });

  final List<int> points;
  final Color color;

  /// Formats the ending value and the two bounds.
  final String currency;

  /// What the series is, in words.
  final String caption;

  /// The overline above the chart.
  final String? label;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) return const SizedBox.shrink();

    final palette = context.money;
    // The scale describes the domain the CHART is drawn against, not the data's
    // own range: with a zero baseline the chart stretches to include zero, and
    // a rail labelled from the data's minimum would disagree with the line
    // beside it while looking authoritative.
    var min = 0, max = 0;
    for (final value in points) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    final last = points.last;

    // A scale bound keeps its sign. Everywhere else a figure is an absolute
    // with a word beside it saying which way it runs; an axis has no room for
    // the word, and dropping the sign there is a falsehood rather than a
    // simplification.
    String bound(int minor) =>
        '${minor < 0 ? '−' : ''}${formatMoney(minor.abs(), currency: currency, base: currency)}';

    final quiet = TextStyle(fontSize: 10, color: palette.inkSubtle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Text(label!, style: context.statLabel),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(bound(max), style: quiet),
                  Text(bound(min), style: quiet),
                ],
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Sparkline(
                  points: points,
                  color: color,
                  height: height,
                  zeroBaseline: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: palette.inkFaint),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              last == 0 ? 'Settled' : bound(last),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: last > 0
                    ? palette.receivable
                    : last < 0
                        ? palette.payable
                        : palette.inkFaint,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
