import '../data/export_models.dart';
import 'money.dart';

/// The workspace export as CSV (milestone 1.9.0, Phase 5).
///
/// The mirror of `web/src/lib/export/csv.ts`, column for column: the same file
/// has to come out of the phone and out of the browser, or a user reconciling
/// the two has a mystery instead of a backup.
///
/// A spreadsheet, not a printout. One row per ledger entry, one column per
/// fact, no merged cells, no totals row.
///
///   * MONEY IS WRITTEN TWICE. `amount_minor` is the integer the database
///     stores; `amount` is that integer rendered with the currency's own
///     minor-unit exponent. They cannot disagree.
///   * CURRENCY IS NEVER COLLAPSED. Every row names the currency the entry was
///     made in beside its amount, with the base equivalent in its own columns.

/// RFC 4180 columns, in the order they are written.
const List<String> kCsvColumns = [
  'entry_id',
  'date',
  'kind',
  'type',
  'direction',
  'scope',
  'person_id',
  'person_name',
  'currency',
  'amount',
  'amount_minor',
  'ledger_currency',
  'ledger_amount',
  'ledger_amount_minor',
  'base_currency',
  'base_amount',
  'base_amount_minor',
  'exchange_rate',
  'exchange_rate_source',
  'conversion_mode',
  'settled_minor',
  'remaining_minor',
  'settlement_status',
  'is_void',
  'transfer_id',
  'transfer_role',
  'note',
  'created_at',
];

/// One CSV field.
///
/// Quoted whenever it contains a delimiter, a quote, a newline, or leading or
/// trailing space — and a quote inside is doubled, which is the whole of RFC
/// 4180's escaping. A name in Devanagari or Arabic needs no escaping at all; it
/// needs the file to be UTF-8, which the writer handles.
String csvField(Object? value) {
  if (value == null) return '';
  final text = value is bool ? (value ? 'true' : 'false') : value.toString();
  if (text.isEmpty) return '';
  final needsQuotes =
      text.contains(',') ||
      text.contains('"') ||
      text.contains('\n') ||
      text.contains('\r') ||
      text.trim() != text;
  return needsQuotes ? '"${text.replaceAll('"', '""')}"' : text;
}

/// One row from already-stringified fields.
String csvRow(List<Object?> fields) => fields.map(csvField).join(',');

String _rateText(int? rateE9) {
  if (rateE9 == null) return '';
  // Nine decimals, trailing zeros trimmed: the figure the ledger stores, not a
  // rounded display version of it.
  final whole = rateE9 ~/ 1000000000;
  final fraction = (rateE9.abs() % 1000000000)
      .toString()
      .padLeft(9, '0')
      .replaceAll(RegExp(r'0+$'), '');
  return fraction.isEmpty ? '$whole' : '$whole.$fraction';
}

String _amount(int? minor, String currency) =>
    minor == null ? '' : minorToInput(minor, currency: currency);

/// One entry as a row of fields, in [kCsvColumns] order.
List<Object?> entryToFields(ExportEntry entry) => [
  entry.id,
  entry.date,
  entry.kind,
  entry.type,
  entry.direction,
  entry.scope,
  entry.personId,
  entry.personName,
  entry.entryCurrency,
  _amount(entry.entryAmountMinor, entry.entryCurrency),
  entry.entryAmountMinor,
  entry.ledgerCurrency,
  _amount(entry.amountMinor, entry.ledgerCurrency),
  entry.amountMinor,
  entry.baseCurrency,
  _amount(entry.amountBaseMinor, entry.baseCurrency),
  entry.amountBaseMinor,
  _rateText(entry.exchangeRateE9),
  entry.exchangeRateSource,
  entry.conversionMode,
  entry.settledMinor,
  entry.remainingMinor,
  entry.settlementStatus,
  entry.isVoid,
  entry.transferId,
  entry.transferRole,
  entry.note,
  entry.createdAt,
];

/// Every entry as a CSV document.
///
/// CRLF line endings, because that is what RFC 4180 says and what a spreadsheet
/// expects from a file it did not write itself.
String entriesToCsv(List<ExportEntry> entries) {
  final lines = <String>[
    csvRow(kCsvColumns),
    for (final entry in entries) csvRow(entryToFields(entry)),
  ];
  return '${lines.join('\r\n')}\r\n';
}

/// The same document with a UTF-8 byte-order mark.
///
/// Excel on Windows reads a BOM-less UTF-8 CSV in the system codepage, which
/// turns every non-Latin name in the file into mojibake. Three bytes, and every
/// other reader ignores them.
String csvWithBom(String csv) => '﻿$csv';
