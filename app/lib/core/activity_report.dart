/// What the Activity report says, before anything is drawn.
///
/// The Activity screen's own shape, in words: day, then the entries of that
/// day, newest first. It is deliberately NOT `core/export_report.dart`, which
/// groups the same rows by account for the workspace report on Profile. Both
/// are true; they answer different questions, and this one answers "what
/// happened, and when?"
///
/// The rules are the same three that govern every other writer here:
///
///   * NOTHING IS COMPUTED. Every figure is a field the database returned.
///     There is no arithmetic in this file — not a sum, not a conversion, not
///     a rate.
///   * CURRENCY IS NEVER COLLAPSED. A row leads with the amount as ENTERED, in
///     the currency it was entered in, exactly as the screen does; the base
///     equivalent and the rate that links them sit underneath.
///   * THE ROWS SAY WHAT THE SCREEN SAYS — including the currency rule: the
///     workspace's own currency is written `₹500`, because the symbol has
///     already said which currency it is, and only a foreign one carries its
///     ISO code, `500 AED`.
///
/// Mirrors `web/src/lib/export/activity-report.ts`.
library;

import 'currencies.dart';
import 'dates.dart';
import 'direction.dart';
import 'export_report.dart' show reportRowType;
import 'money.dart';
import '../data/export_models.dart';

/// The three tabs on the Activity screen.
enum ActivityView {
  all,
  transaction,
  settlement;

  /// The word the document uses for this category.
  String get label => switch (this) {
    ActivityView.all => 'Everything',
    ActivityView.transaction => 'Transactions',
    ActivityView.settlement => 'Settlements',
  };

  /// The `kinds` filter this tab maps onto. Null is "no kind filter".
  List<String>? get kinds => switch (this) {
    ActivityView.all => null,
    ActivityView.transaction => const ['credit', 'debit'],
    ActivityView.settlement => const ['settlement'],
  };

  /// The Activity screen's own `kind` value, so the two stay in step.
  static ActivityView fromKind(String? kind) => switch (kind) {
    'transaction' => ActivityView.transaction,
    'settlement' => ActivityView.settlement,
    _ => ActivityView.all,
  };
}

/// The dates an export covers. Both null is the whole feed.
class ActivityRange {
  const ActivityRange({this.from, this.to});

  /// One day, as a range whose ends are the same day.
  const ActivityRange.day(String day) : from = day, to = day;

  /// The whole feed.
  static const ActivityRange all = ActivityRange();

  final String? from;
  final String? to;

  bool get isAll => from == null && to == null;
  bool get isSingleDay => from != null && from == to;

  /// True when the ends are the wrong way round.
  ///
  /// The database would happily return nothing for it, but "nothing" is a bad
  /// answer to a question the user did not mean to ask, so the sheet refuses to
  /// export until it is fixed.
  bool get isBackwards => from != null && to != null && from!.compareTo(to!) > 0;

  /// True while only one end has been picked.
  bool get isIncomplete => (from == null) != (to == null);
}

/// What the document says it is showing.
///
///     All activity
///     04 Sept 2026
///     28 Aug 2026 → 04 Sept 2026
String activityScopeLabel(ActivityRange range) {
  final from = range.from;
  final to = range.to;
  if (from == null && to == null) return 'All activity';
  if (from != null && to != null) {
    return from == to
        ? statementDate(from)
        : '${statementDate(from)} → ${statementDate(to)}';
  }
  return from != null ? 'From ${statementDate(from)}' : 'Up to ${statementDate(to!)}';
}

/// The filename: named after what is in it, dated, sortable in a folder.
///
/// Built here rather than through `exportFilename()`, which appends a date of
/// its own — the dates in an Activity export's name are the ones it covers, and
/// a name carrying both said the day twice.
///
/// Mirrors `activityExportFilename()` in `web/src/lib/export/activity.ts`.
String activityExportFilename(
  String extension,
  ActivityView view,
  ActivityRange range, {
  DateTime? today,
}) {
  final parts = <String>['accounic', 'activity'];
  if (view != ActivityView.all) {
    parts.add(view == ActivityView.transaction ? 'transactions' : 'settlements');
  }

  final from = range.from;
  final to = range.to;
  if (from != null && to != null && from != to) {
    parts.addAll([from, 'to', to]);
  } else if (from != null || to != null) {
    parts.add((from ?? to)!);
  } else {
    parts.add(isoDate(today ?? DateTime.now()));
  }
  return '${parts.join('-')}.$extension';
}

/// How this report writes money.
///
/// Not `StatementFormatter`: that one names every figure with its ISO code,
/// which is right for the workspace report and wrong here. An Activity row
/// states the base currency constantly, so repeating `INR` after every `₹` is
/// noise — the base is passed in and the presenter drops the code for it.
class ActivityFormatter {
  const ActivityFormatter({this.money = _defaultMoney, this.approx = _defaultApprox});

  /// `₹500` for the base currency, `500 AED` for anything else.
  final String Function(int minor, String? currency, String base) money;

  /// `≈ ₹12,962.50` — a conversion is always into the base, so no code.
  final String Function(int minor, String? currency) approx;

  static String _defaultMoney(int minor, String? currency, String base) =>
      formatMoney(minor, currency: currency, base: base);

  static String _defaultApprox(int minor, String? currency) =>
      formatApprox(minor, currency: currency);
}

/// The screen's formatter, and the one the PDF uses too.
const kActivityFormatter = ActivityFormatter();

/// One entry, as the report states it.
class ActivityReportRow {
  const ActivityReportRow({
    required this.person,
    required this.type,
    required this.description,
    required this.amount,
    required this.equivalent,
    required this.rate,
    required this.rateNote,
    required this.settlement,
    required this.receivable,
    required this.isSettlement,
    required this.isOpening,
    required this.time,
  });

  /// The account the entry belongs to — the row's heading, as on screen.
  final String person;

  /// `Credit`, `Settlement received`, `Transfer to …`, `Opening balance`.
  final String type;

  /// The note, when it says something the label does not. Empty otherwise.
  final String description;

  /// The figure as entered, in the currency it was entered in.
  final String amount;

  /// `≈ ₹12,962.50` — the base equivalent, when there is one worth printing.
  final String? equivalent;

  /// `1 AED = ₹25.925 INR`, or null when nothing was converted.
  final String? rate;

  /// `Custom rate`, `Amount entered by hand`, both, or null.
  final String? rateNote;

  /// `Settled`, `Open`, `₹400 of ₹1,000` — for a transaction that can settle.
  final String? settlement;

  /// Which way the debt runs. Drives the glyph and the amount's colour.
  final bool receivable;
  final bool isSettlement;
  final bool isOpening;

  /// `08:42 PM`, from `created_at`: when the row was actually written.
  final String time;
}

/// One day, and everything that happened on it.
class ActivityReportDay {
  const ActivityReportDay({
    required this.date,
    required this.label,
    required this.rows,
  });

  /// `2026-09-04` — the day itself, for anything that needs to sort.
  final String date;

  /// `Today`, `Tuesday`, `28 August` — the screen's own words, and the only
  /// words: a heading that printed the label and the full date said the same
  /// thing twice. The date the document was generated is on the cover.
  final String label;

  final List<ActivityReportRow> rows;

  int get count => rows.length;
}

/// The whole report, ready to draw.
class ActivityReport {
  const ActivityReport({
    required this.title,
    required this.workspaceName,
    required this.ownerName,
    required this.exportedAt,
    required this.category,
    required this.scope,
    required this.baseCurrency,
    required this.days,
    required this.entryCount,
    required this.truncated,
  });

  final String title;
  final String workspaceName;
  final String? ownerName;
  final String exportedAt;

  /// `Everything`, `Transactions`, `Settlements`.
  final String category;

  /// `All activity`, `04 Sept 2026`, or `28 Aug 2026 → 04 Sept 2026`.
  final String scope;

  final String baseCurrency;
  final List<ActivityReportDay> days;
  final int entryCount;

  /// Set when the export hit its size cap: printed, never hidden.
  final bool truncated;

  int get dayCount => days.length;
}

/// How much of a transaction is settled, in one phrase, or null.
String? activitySettlement(ExportEntry entry, ActivityFormatter format, String base) {
  if (entry.isSettlement) return null;
  final status = entry.settlementStatus;
  if (status == null) return null;
  if (status == 'settled') return 'Settled';
  if (status == 'open') return 'Open';

  final settled = format.money(entry.settledMinor ?? 0, entry.ledgerCurrency, base);
  final total = format.money(entry.amountMinor, entry.ledgerCurrency, base);
  return '$settled of $total';
}

ActivityReportRow _toRow(ExportEntry entry, ActivityFormatter format, String base) {
  final type = reportRowType(entry);
  final note = (entry.note ?? '').trim();

  // The equivalent earns its line only when it says something the primary
  // figure does not — the same test the screen applies.
  final converted =
      entry.amountBaseMinor != null && entry.baseCurrency != entry.entryCurrency;

  final rateE9 = entry.exchangeRateE9;
  final rate = rateE9 == null
      ? null
      : rateSentence(
          entry.entryCurrency,
          entry.ledgerCurrency,
          rateE9,
          amountMinor: entry.entryAmountMinor,
        );

  // Both can be true at once and the screen says both: a rate typed by hand,
  // and an amount typed over the one that rate produced.
  final notes = <String>[
    if (rateIsManual(entry.exchangeRateSource)) 'Custom rate',
    if (entry.conversionMode == 'manual') 'Amount entered by hand',
  ];

  return ActivityReportRow(
    person: entry.personName ?? '—',
    type: type,
    // An opening balance is stored with "Opening balance" as its note, so a row
    // would otherwise print the phrase twice.
    description: note.isNotEmpty && note != type ? note : '',
    amount: format.money(entry.entryAmountMinor, entry.entryCurrency, base),
    equivalent: converted ? format.approx(entry.amountBaseMinor!, entry.baseCurrency) : null,
    rate: rate,
    rateNote: notes.isEmpty ? null : notes.join(' · '),
    settlement: activitySettlement(entry, format, base),
    receivable: entryIsReceivable(entry.type),
    isSettlement: entry.isSettlement,
    isOpening: entry.isOpening,
    time: timeOfDay(entry.createdAt),
  );
}

/// The entries, grouped into days, newest first.
///
/// `export_entries()` returns them oldest-first and deterministically
/// tie-broken; the Activity screen reads newest-first. This reverses that one
/// ordering and changes nothing else.
List<ActivityReportDay> groupEntriesByDay(
  List<ExportEntry> entries,
  ActivityFormatter format,
  String base,
) {
  final buckets = <String, List<ExportEntry>>{};
  for (final entry in entries) {
    buckets.putIfAbsent(entry.date, () => []).add(entry);
  }

  final dates = buckets.keys.toList()..sort((a, b) => b.compareTo(a));

  return [
    for (final date in dates)
      ActivityReportDay(
        date: date,
        label: dayGroupLabel(date),
        // Within a day the screen shows the most recently written first.
        rows: buckets[date]!.reversed.map((e) => _toRow(e, format, base)).toList(),
      ),
  ];
}

/// The whole report, ready to draw.
ActivityReport buildActivityReport(
  ExportBundle bundle, {
  required ActivityView view,
  required String scopeLabel,
  ActivityFormatter format = kActivityFormatter,
}) {
  final header = bundle.header;
  final base = header.baseCurrency;

  return ActivityReport(
    title: 'Activity report',
    workspaceName: header.workspaceName,
    ownerName: (header.workspace['name'] as String?)?.trim(),
    exportedAt: header.exportedAt,
    category: view.label,
    scope: scopeLabel,
    baseCurrency: base,
    days: groupEntriesByDay(bundle.entries, format, base),
    entryCount: bundle.entries.length,
    truncated: bundle.truncated,
  );
}
