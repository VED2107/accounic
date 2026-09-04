/// Picking a date, and picking two (context.md §18, §29).
///
/// Material ships a perfectly correct calendar, and for a release it was the
/// one this app used. The trouble is that it is *Material's* calendar: its own
/// radii, its own accent, its own header, dropped on top of a product that has
/// spent a release deciding what those should be. Next to an Accounic sheet it
/// reads as a different application borrowed for a moment.
///
/// So the grid is ours. It is deliberately small — a month you can walk, a
/// highlighted span, two taps — and it is one widget used by every date in the
/// product, so a date is picked the same way wherever it is picked.
///
/// What it is not is a date library: it does arithmetic on a local [DateTime]
/// and formats through `core/dates.dart`, both of which already exist.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/layout.dart';
import '../../core/theme.dart';
import '../motion.dart';

/// The calendar, as a sheet. Returns the chosen day, or null if dismissed.
Future<DateTime?> showAccounicDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'Pick a date',
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _PickerSheet(
      title: title,
      child: AccounicCalendar(
        initialMonth: initialDate,
        selected: initialDate,
        firstDate: firstDate,
        lastDate: lastDate,
        onPick: (day) => Navigator.of(context).pop(day),
      ),
    ),
  );
}

/// The same calendar, picking two ends. Returns null if dismissed.
Future<DateTimeRange?> showAccounicDateRangePicker(
  BuildContext context, {
  DateTimeRange? initialRange,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = 'Pick a date range',
}) {
  return showModalBottomSheet<DateTimeRange>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _PickerSheet(
      title: title,
      child: _RangeBody(
        initialRange: initialRange,
        firstDate: firstDate,
        lastDate: lastDate,
      ),
    ),
  );
}

/* -------------------------------------------------------------------------- */

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.money;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(AppRadius.panel),
          border: Border.all(color: palette.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(AppIcons.close),
                  iconSize: AppIconSize.sm,
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

class _RangeBody extends StatefulWidget {
  const _RangeBody({this.initialRange, this.firstDate, this.lastDate});

  final DateTimeRange? initialRange;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<_RangeBody> createState() => _RangeBodyState();
}

class _RangeBodyState extends State<_RangeBody> {
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _from = widget.initialRange?.start;
    _to = widget.initialRange?.end;
  }

  void _pick(DateTime day) {
    setState(() {
      // First tap sets the start and clears the end; the second closes the
      // range — and a day before the start restarts from there rather than
      // producing a backwards range nobody meant.
      if (_from == null || _to != null || day.isBefore(_from!)) {
        _from = day;
        _to = null;
      } else {
        _to = day;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final complete = _from != null && _to != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccounicCalendar(
          initialMonth: _from ?? DateTime.now(),
          rangeStart: _from,
          rangeEnd: _to,
          firstDate: widget.firstDate,
          lastDate: widget.lastDate,
          onPick: _pick,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          _from == null
              ? 'Pick the start of the range'
              : _to == null
              ? 'Now pick the end'
              : '${statementDate(isoDate(_from!))} → ${statementDate(isoDate(_to!))}',
          style: TextStyle(fontSize: 12, color: palette.inkMuted),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: complete
                    ? () => Navigator.of(
                        context,
                      ).pop(DateTimeRange(start: _from!, end: _to!))
                    : null,
                child: const Text('Use these dates'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */

/// The month grid itself, usable on its own where a sheet is not wanted.
class AccounicCalendar extends StatefulWidget {
  const AccounicCalendar({
    super.key,
    required this.onPick,
    required this.initialMonth,
    this.selected,
    this.rangeStart,
    this.rangeEnd,
    this.firstDate,
    this.lastDate,
  });

  final ValueChanged<DateTime> onPick;
  final DateTime initialMonth;

  /// A single chosen day, for the one-date picker.
  final DateTime? selected;

  /// The two ends, for the range picker.
  final DateTime? rangeStart;
  final DateTime? rangeEnd;

  final DateTime? firstDate;

  /// Defaults to today: a ledger has no future.
  final DateTime? lastDate;

  @override
  State<AccounicCalendar> createState() => _AccounicCalendarState();
}

class _AccounicCalendarState extends State<AccounicCalendar> {
  late DateTime _month;

  static const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
  }

  DateTime get _first => widget.firstDate ?? DateTime(2000);
  DateTime get _last => widget.lastDate ?? DateTime.now();

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  /// The six weeks a month grid always shows, so the sheet never changes height.
  List<DateTime> get _days {
    final first = DateTime(_month.year, _month.month);
    // Monday-first, which is what the rest of this product assumes.
    final lead = (first.weekday + 6) % 7;
    final start = first.subtract(Duration(days: lead));
    return [for (var i = 0; i < 42; i += 1) DateTime(start.year, start.month, start.day + i)];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.money;
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _MonthStep(
              icon: AppIcons.previous,
              tooltip: 'Previous month',
              onTap: () => setState(
                () => _month = DateTime(_month.year, _month.month - 1),
              ),
            ),
            Expanded(
              child: Text(
                DateFormat('MMMM yyyy').format(_month),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
            _MonthStep(
              icon: AppIcons.forward,
              tooltip: 'Next month',
              onTap: () => setState(
                () => _month = DateTime(_month.year, _month.month + 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            for (final day in _weekdays)
              Expanded(
                child: Text(
                  day,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: palette.inkFaint,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        for (var week = 0; week < 6; week += 1)
          Row(
            children: [
              for (final day in _days.skip(week * 7).take(7))
                Expanded(child: _cell(day, palette, scheme, today)),
            ],
          ),
      ],
    );
  }

  Widget _cell(
    DateTime day,
    AccounicColors palette,
    ColorScheme scheme,
    DateTime today,
  ) {
    final outside = day.month != _month.month;
    final beyond = day.isAfter(_last) || day.isBefore(_first);

    final isStart = _sameDay(widget.rangeStart, day);
    final isEnd = _sameDay(widget.rangeEnd, day);
    final isSelected = _sameDay(widget.selected, day) || isStart || isEnd;
    final inSpan =
        widget.rangeStart != null &&
        widget.rangeEnd != null &&
        day.isAfter(widget.rangeStart!) &&
        day.isBefore(widget.rangeEnd!);

    // The span is a continuous band, so its rounding lives on the two ends
    // rather than on every cell.
    final radius = isSelected
        ? BorderRadius.circular(AppRadius.field)
        : inSpan
        ? BorderRadius.zero
        : BorderRadius.circular(AppRadius.field);

    return Semantics(
      button: !beyond,
      selected: isSelected,
      label: fullDate(isoDate(day)),
      child: Pressable(
        onTap: beyond ? null : () => widget.onPick(day),
        scale: 0.94,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary
                : inSpan
                ? scheme.primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: radius,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: beyond
                      ? palette.inkFaint.withValues(alpha: 0.5)
                      : isSelected
                      ? scheme.onPrimary
                      : outside
                      ? palette.inkFaint
                      : scheme.onSurface,
                ),
              ),
              if (_sameDay(today, day) && !isSelected) ...[
                const SizedBox(height: 2),
                Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthStep extends StatelessWidget {
  const _MonthStep({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.field),
            color: context.money.sunken,
          ),
          child: Icon(icon, size: AppIconSize.sm, color: context.money.inkMuted),
        ),
      ),
    );
  }
}
