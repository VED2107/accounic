import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../motion.dart';

/// Thirty days of flow, with the day under the finger named (upgrade §8).
///
/// The sparkline beside the net position says what the shape is; this says what
/// happened. Each day is a column above and below a baseline — received above in
/// green, given below in red — because money in and money out are opposite
/// directions, and drawing them as two stacked positives makes the reader do the
/// subtraction themselves.
///
/// Settled has no column. It is not a flow between the two of you, it is one of
/// those flows being closed, so a third bar would count the same money twice on
/// the same day. It is in the readout instead.
///
/// Interaction is a drag, not a hover: this is the touch client, and a chart
/// whose detail is only reachable with a pointer has no detail here at all. The
/// desktop build gets the same gesture from a mouse drag, and both fall back to
/// the totals above the plot, which are readable with no interaction at all.
/// The web client's `ActivityChart` is the same design.
class ActivityChart extends StatefulWidget {
  const ActivityChart({
    super.key,
    required this.buckets,
    required this.currency,
    this.height = 108,
  });

  /// As the RPC returns them — any order; sorted here.
  final List<ActivityBucket> buckets;
  final String currency;
  final double height;

  @override
  State<ActivityChart> createState() => _ActivityChartState();
}

class _ActivityChartState extends State<ActivityChart> {
  int? _active;

  List<ActivityBucket> get _days {
    final days = [...widget.buckets]..sort((a, b) => a.bucket.compareTo(b.bucket));
    return days;
  }

  void _pick(double dx, double width, int count) {
    if (count < 2 || width <= 0) return;
    final ratio = dx / width;
    final index = (ratio * (count - 1)).round().clamp(0, count - 1);
    if (index != _active) setState(() => _active = index);
  }

  @override
  Widget build(BuildContext context) {
    final days = _days;
    if (days.length < 2) return const SizedBox.shrink();

    final palette = context.money;

    var peak = 1;
    var credit = 0;
    var debit = 0;
    var settled = 0;
    for (final day in days) {
      if (day.credit > peak) peak = day.credit;
      if (day.debit > peak) peak = day.debit;
      credit += day.credit;
      debit += day.debit;
      settled += day.settled;
    }

    final shown = _active == null ? null : days[_active!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The chart means something before it is touched, which is the test of
        // whether the readout is a convenience or load-bearing.
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          children: [
            _Legend(
              color: palette.receivable,
              label: 'You received',
              value: formatMinor(credit, currency: widget.currency),
            ),
            _Legend(
              color: palette.payable,
              label: 'You gave',
              value: formatMinor(debit, currency: widget.currency),
            ),
            _Legend(
              color: palette.inkFaint,
              label: 'Settled',
              value: formatMinor(settled, currency: widget.currency),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // The readout occupies its slot whether or not a day is selected, so
        // touching the chart does not push the rest of the card down.
        SizedBox(
          height: 34,
          child: AnimatedSwitcher(
            duration: Motion.fast,
            child: shown == null
                ? Align(
                    key: const ValueKey('hint'),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Touch the chart for a single day.',
                      style: TextStyle(fontSize: 12, color: palette.inkFaint),
                    ),
                  )
                : Row(
                    key: ValueKey(shown.bucket),
                    children: [
                      Text(
                        _dayLabel(shown.bucket),
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.colors.onSurface,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.md,
                          children: [
                            _Readout(
                              color: palette.receivable,
                              value: formatMinor(shown.credit, currency: widget.currency),
                            ),
                            _Readout(
                              color: palette.payable,
                              value: formatMinor(shown.debit, currency: widget.currency),
                            ),
                            _Readout(
                              color: palette.inkFaint,
                              value: formatMinor(shown.settled, currency: widget.currency),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _pick(details.localPosition.dx, width, days.length),
              // Horizontal only: a vertical drag has to keep scrolling the page.
              onHorizontalDragUpdate: (details) =>
                  _pick(details.localPosition.dx, width, days.length),
              // The selection HOLDS after the finger lifts. Clearing it on
              // release would mean the readout only exists while the finger is
              // covering the chart, which is the touch equivalent of a tooltip
              // that vanishes when you look at it.
              onTapCancel: () => setState(() => _active = null),
              child: SizedBox(
                height: widget.height,
                child: Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < days.length; i++)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 0.5),
                              child: _Column(
                                credit: days[i].credit,
                                debit: days[i].debit,
                                peak: peak,
                                active: i == _active,
                              ),
                            ),
                          ),
                      ],
                    ),
                    // The zero line. Half the plot above it, half below, so the
                    // two directions are comparable at a glance.
                    Align(
                      alignment: Alignment.center,
                      child: Container(height: 1, color: palette.lineStrong),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _dayLabel(days.first.bucket),
              style: TextStyle(fontSize: 11, color: palette.inkFaint),
            ),
            Text(
              _dayLabel(days.last.bucket),
              style: TextStyle(fontSize: 11, color: palette.inkFaint),
            ),
          ],
        ),
      ],
    );
  }
}

/// One day: received above the line, given below it.
class _Column extends StatelessWidget {
  const _Column({
    required this.credit,
    required this.debit,
    required this.peak,
    required this.active,
  });

  final int credit;
  final int debit;
  final int peak;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    // A day with a real but tiny amount still gets a visible mark: a column
    // that rounds to nothing reads as a day when nothing happened, which is a
    // different fact.
    double share(int value) => value == 0 ? 0 : (value / peak).clamp(0.02, 1.0);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? palette.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(2),
      ),
      child: Column(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: share(credit),
                widthFactor: 1,
                child: _Bar(
                  color: palette.receivable,
                  active: active,
                  radius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
              ),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: FractionallySizedBox(
                heightFactor: share(debit),
                widthFactor: 1,
                child: _Bar(
                  color: palette.payable,
                  active: active,
                  radius: const BorderRadius.vertical(bottom: Radius.circular(2)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.color, required this.active, required this.radius});

  final Color color;
  final bool active;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: Motion.fast,
      opacity: active ? 1 : 0.8,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, borderRadius: radius),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: context.money.inkMuted),
        ),
        const SizedBox(width: AppSpacing.xs + 2),
        Text(value, style: context.moneyStyle(MoneySize.small)),
      ],
    );
  }
}

class _Readout extends StatelessWidget {
  const _Readout({required this.color, required this.value});

  final Color color;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs + 1),
        Text(value, style: context.moneyStyle(MoneySize.small, color: color)),
      ],
    );
  }
}

/// "24 Aug" — the axis and the readout agree on how a day is written.
String _dayLabel(String bucket) {
  final date = DateTime.tryParse(bucket.length >= 10 ? bucket.substring(0, 10) : bucket);
  if (date == null) return bucket;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${date.day} ${months[date.month - 1]}';
}
