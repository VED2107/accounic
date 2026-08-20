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

/// Groups dated rows into the day buckets the timeline renders.
List<({String date, String label, List<T> items})> groupByDate<T>(
  List<T> rows,
  String Function(T) dateOf,
) {
  final buckets = <String, List<T>>{};
  for (final row in rows) {
    final key = dateOf(row).substring(0, 10);
    buckets.putIfAbsent(key, () => <T>[]).add(row);
  }
  final keys = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final key in keys)
      (date: key, label: friendlyDate(key), items: buckets[key]!),
  ];
}
