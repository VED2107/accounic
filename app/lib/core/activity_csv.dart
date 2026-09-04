/// The Activity feed as CSV.
///
/// A spreadsheet is a table, so this is a table — but it is the *Activity*
/// table, not the workspace one. Two things make it that rather than a rename
/// of `core/export_csv.dart`:
///
///   * THE ORDER IS THE SCREEN'S. Newest first, the way the feed reads. A CSV
///     sorted by person would be the workspace export with different headings,
///     which is the thing this feature exists not to be.
///   * THE COLUMNS ARE THE ROW'S. Day and time beside the date, the entry's own
///     words for its type, and the amount as entered next to its currency.
///
/// Mirrors `web/src/lib/export/activity-csv.ts`.
library;

import 'activity_report.dart';
import 'dates.dart';
import 'export_csv.dart' show csvRow;
import 'export_report.dart' show reportRowType;
import 'money.dart';
import '../data/export_models.dart';

/// RFC 4180 columns, in the order they are written.
const List<String> kActivityCsvColumns = [
  'date',
  'day',
  'time',
  'person',
  'type',
  'description',
  'amount',
  'currency',
  'base_amount',
  'base_currency',
  'exchange_rate',
  'rate_source',
  'status',
];

String _rateText(int? rateE9) {
  if (rateE9 == null) return '';
  // Nine decimals with trailing zeros trimmed: the figure the ledger stores,
  // not a rounded display version of it.
  final whole = rateE9 ~/ 1000000000;
  var fraction = (rateE9.abs() % 1000000000).toString().padLeft(9, '0');
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

String _amount(int? minor, String? currency) =>
    minor == null ? '' : minorToInput(minor, currency: currency ?? 'INR');

/// One entry as a row of fields, in [kActivityCsvColumns] order.
List<Object?> activityEntryToFields(
  ExportEntry entry,
  ActivityFormatter format,
  String base,
) {
  final type = reportRowType(entry);
  final note = (entry.note ?? '').trim();

  return [
    entry.date,
    dayGroupLabel(entry.date),
    timeOfDay(entry.createdAt),
    entry.personName,
    type,
    note == type ? '' : note,
    _amount(entry.entryAmountMinor, entry.entryCurrency),
    entry.entryCurrency,
    _amount(entry.amountBaseMinor, entry.baseCurrency),
    entry.amountBaseMinor == null ? '' : entry.baseCurrency,
    _rateText(entry.exchangeRateE9),
    entry.exchangeRateSource,
    activitySettlement(entry, format, base),
  ];
}

/// Every entry as a CSV document, newest first.
///
/// The reversal is the only reordering: `export_entries()` returns the rows
/// oldest-first, and the feed reads the other way.
String activityEntriesToCsv(
  List<ExportEntry> entries,
  String base, {
  ActivityFormatter format = kActivityFormatter,
}) {
  final lines = <String>[
    csvRow(kActivityCsvColumns),
    for (final entry in entries.reversed)
      csvRow(activityEntryToFields(entry, format, base)),
  ];
  // CRLF, because that is what RFC 4180 says and what Excel expects.
  return '${lines.join('\r\n')}\r\n';
}
