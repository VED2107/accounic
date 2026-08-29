library;

import 'package:intl/intl.dart';

/// Date presentation (context.md §16).
///
/// Dates arrive as plain `YYYY-MM-DD` calendar dates. They are parsed into
/// local time deliberately: `DateTime.parse` on a bare date yields UTC
/// midnight, which renders as the previous day for anyone west of Greenwich.

DateTime parseDbDate(String value) {
  final parts = value.substring(0, 10).split('-');
  return DateTime(
    int.parse(parts[0]),
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
}

String todayIso() => DateFormat('yyyy-MM-dd').format(DateTime.now());

String isoDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

int _dayDiff(DateTime a, DateTime b) =>
    DateTime(a.year, a.month, a.day)
        .difference(DateTime(b.year, b.month, b.day))
        .inDays;

/// "Today", "Yesterday", "12 Aug", or "12 Aug 2024" once the year differs.
String friendlyDate(String value) {
  final date = parseDbDate(value);
  final now = DateTime.now();
  final diff = _dayDiff(now, date);

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff == -1) return 'Tomorrow';

  return DateFormat(date.year == now.year ? 'd MMM' : 'd MMM yyyy').format(date);
}

String fullDate(String value) =>
    DateFormat('d MMMM yyyy').format(parseDbDate(value));

/// `28 Aug 2026` — the form a statement prints, unambiguous in any locale and
/// never relative. Twin of `statementDate()` in `web/src/lib/dates.ts`.
String statementDate(String value) {
  if (value.isEmpty) return '';
  return DateFormat('d MMM yyyy').format(parseDbDate(value));
}

/// `08:42 PM` — the time of day a row was recorded, from its timestamp.
///
/// Empty when the value carries no usable time, which is what a bare calendar
/// date is. A statement prints the time beside the date because two entries on
/// one day are otherwise indistinguishable on paper.
String timeOfDay(String isoTimestamp) {
  if (isoTimestamp.length <= 10) return '';
  final parsed = DateTime.tryParse(isoTimestamp);
  if (parsed == null) return '';
  return DateFormat('hh:mm a').format(parsed.toLocal());
}

String relativeTime(String isoTimestamp) {
  final then = DateTime.parse(isoTimestamp).toLocal();
  final seconds = DateTime.now().difference(then).inSeconds;

  if (seconds < 60) return 'just now';
  if (seconds < 3600) return '${seconds ~/ 60}m ago';
  if (seconds < 86400) return '${seconds ~/ 3600}h ago';
  if (seconds < 2592000) return '${seconds ~/ 86400}d ago';
  return DateFormat('d MMM yyyy').format(then);
}

String greeting([DateTime? now]) {
  final hour = (now ?? DateTime.now()).hour;
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/// A heading for a day of activity.
///
/// Inside the last week people think in weekdays — "that was Tuesday" — and
/// beyond it they think in dates, so the label switches at seven days rather
/// than trying to be clever about it. Matches the web client's dayGroupLabel.
String dayGroupLabel(String value) {
  final date = parseDbDate(value);
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(date.year, date.month, date.day))
      .inDays;

  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days > 1 && days < 7) return DateFormat('EEEE').format(date);

  return DateFormat(date.year == now.year ? 'd MMMM' : 'd MMMM y').format(date);
}

/// Groups dated rows into the day buckets the timeline renders.
List<({String date, String label, List<T> items})> groupByDate<T>(
  List<T> rows,
  String Function(T) dateOf, {
  String Function(String)? label,
}) {
  final buckets = <String, List<T>>{};
  for (final row in rows) {
    final key = dateOf(row).substring(0, 10);
    buckets.putIfAbsent(key, () => <T>[]).add(row);
  }
  final keys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final key in keys)
      (date: key, label: (label ?? friendlyDate)(key), items: buckets[key]!),
  ];
}
