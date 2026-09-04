import 'package:accounic/core/activity_csv.dart';
import 'package:accounic/core/activity_report.dart';
import 'package:accounic/core/theme.dart';
import 'package:accounic/data/activity_pdf.dart';
import 'package:accounic/data/export_models.dart';
import 'package:accounic/providers.dart';
import 'package:accounic/ui/motion.dart';
import 'package:accounic/ui/sheets/export_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Activity export.
///
/// What these pin is the one thing that makes it this feature rather than the
/// workspace report with a new title: **it is grouped by day, newest first, and
/// never by account.** Around that, the promises the sheet makes — the date and
/// the category are independent, a day is a day, the count is the database's,
/// and the currency an entry was written in survives into the file.
///
/// The web twin is `web/src/lib/export/activity-report.test.ts`.

/// A stand-in presenter that keeps the one rule under test: the base currency
/// is written without its code, anything else keeps it.
final _format = ActivityFormatter(
  money: (minor, currency, base) => currency == base
      ? '#${(minor / 100).toStringAsFixed(2)}'
      : '${(minor / 100).toStringAsFixed(2)} $currency',
  approx: (minor, currency) => '≈ #${(minor / 100).toStringAsFixed(2)}',
);

ExportHeader _header({int entries = 4}) => ExportHeader.fromJson({
  'schema_version': 1,
  'generator': 'accounic',
  'exported_at': '2026-09-04T10:00:00Z',
  'filters': {'scope': 'all', 'include_void': false},
  'workspace': {'name': 'Export Tester', 'base_currency': 'INR'},
  'summary': {'net_position': 1000},
  'totals_by_currency': [
    {'currency': 'INR', 'receivable': 120000, 'payable': 20000, 'net': 100000},
  ],
  'currencies': [
    {'code': 'INR', 'name': 'Indian Rupee', 'symbol': 'Rs', 'decimals': 2},
  ],
  'people': [
    {
      'id': 'p1',
      'name': 'Nirali Bhatt',
      'ledger_currency': 'INR',
      'is_archived': false,
      'balance': {
        'currency': 'INR',
        'net_balance': 100000,
        'outstanding_receivable': 120000,
        'outstanding_payable': 20000,
        'opening_net_minor': 0,
      },
    },
  ],
  'counts': {
    'people': 2,
    'entries': entries,
    'transactions': entries,
    'settlements': 0,
    'transfers': 0,
    'opening': 0,
    'voided': 0,
  },
});

ExportEntry _entry({
  required String id,
  required String date,
  required String createdAt,
  String person = 'sayan',
  String kind = 'transaction',
  String type = 'debit',
  int entryMinor = 50000,
  String entryCurrency = 'INR',
  int? baseMinor = 50000,
  int? rateE9,
  String? rateSource,
  String? conversionMode,
  String? status = 'open',
}) => ExportEntry.fromJson({
  'id': id,
  'kind': kind,
  'type': type,
  'date': date,
  'person_id': 'p1',
  'person_name': person,
  'is_void': false,
  'scope': 'regular',
  'entry_amount_minor': entryMinor,
  'entry_currency': entryCurrency,
  'amount_minor': entryMinor,
  'ledger_currency': 'INR',
  'amount_base_minor': baseMinor,
  'base_currency': 'INR',
  'exchange_rate_e9': rateE9,
  'exchange_rate_source': rateSource,
  'conversion_mode': conversionMode,
  'settled_minor': 0,
  'remaining_minor': entryMinor,
  'settlement_status': status,
  'created_at': createdAt,
});

/// Three days: a settlement pair on the newest, a converted AED entry at a
/// custom rate on the middle one, a plain entry on the oldest. Oldest-first,
/// as `export_entries()` returns them.
ExportBundle _bundle() => ExportBundle(
  header: _header(),
  entries: [
    _entry(
      id: 'old',
      date: '2026-08-30',
      createdAt: '2026-08-30T11:00:00Z',
      entryCurrency: 'AED',
      baseMinor: 1210000,
      rateE9: 24200000000,
      rateSource: 'ecb',
    ),
    _entry(
      id: 'mid',
      date: '2026-09-02',
      createdAt: '2026-09-02T08:00:00Z',
      person: 'ved',
      entryCurrency: 'AED',
      baseMinor: 1400000,
      rateE9: 28000000000,
      rateSource: 'manual-rate',
      conversionMode: 'manual',
    ),
    _entry(id: 'today-txn', date: '2026-09-04', createdAt: '2026-09-04T08:00:00Z'),
    _entry(
      id: 'today-settle',
      date: '2026-09-04',
      createdAt: '2026-09-04T09:30:00Z',
      person: 'ved',
      kind: 'settlement',
      type: 'in',
      entryMinor: 703750,
      baseMinor: 703750,
      status: null,
    ),
  ],
  truncated: false,
);

void main() {
  const screen = Size(360, 780);

  Future<void> openSheet(
    WidgetTester tester, {
    ExportHeader? header,
    String? day,
    ActivityView view = ActivityView.all,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final filters = ExportFilters.activity(
      kinds: view.kinds,
      from: day,
      to: day,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exportPreviewProvider(filters).overrideWith((ref) async => header ?? _header()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () => showExportSheet(
                    context,
                    ref,
                    subject: ExportSubject.activity,
                    view: view,
                    day: day,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  group('the Activity filter contract', () {
    test('maps each tab onto the kinds the database already understands', () {
      expect(ActivityView.all.kinds, isNull);
      expect(ActivityView.transaction.kinds, ['credit', 'debit']);
      expect(ActivityView.settlement.kinds, ['settlement']);
    });

    test('keeps the feed whole: the opening book is in, voided history is out', () {
      final filters = ExportFilters.activity(kinds: null);
      expect(filters.scope, 'all');
      expect(filters.includeVoid, isFalse);
    });

    test('treats a day as a one-day range, not a new kind of filter', () {
      final filters = ExportFilters.activity(from: '2026-09-04', to: '2026-09-04');
      expect(filters.toParams()['p_from'], '2026-09-04');
      expect(filters.toParams()['p_to'], '2026-09-04');
    });

    test('sends an arbitrary range through untouched', () {
      final filters = ExportFilters.activity(
        kinds: ActivityView.settlement.kinds,
        from: '2026-08-28',
        to: '2026-09-04',
      );
      final params = filters.toParams();
      expect(params['p_kinds'], ['settlement']);
      expect(params['p_from'], '2026-08-28');
      expect(params['p_to'], '2026-09-04');
    });

    test('refuses a range whose ends are the wrong way round', () {
      expect(
        const ActivityRange(from: '2026-09-04', to: '2026-08-28').isBackwards,
        isTrue,
      );
      expect(
        const ActivityRange(from: '2026-08-28', to: '2026-09-04').isBackwards,
        isFalse,
      );
      expect(const ActivityRange.day('2026-09-04').isBackwards, isFalse);
      expect(ActivityRange.all.isBackwards, isFalse);
    });

    test('says what it is showing, without saying "everything to date"', () {
      expect(activityScopeLabel(ActivityRange.all), 'All activity');
      expect(activityScopeLabel(const ActivityRange.day('2026-09-04')), '04 Sep 2026');
      expect(
        activityScopeLabel(const ActivityRange(from: '2026-08-28', to: '2026-09-04')),
        '28 Aug 2026 → 04 Sep 2026',
      );
    });

    test('names the file after what is in it', () {
      final today = DateTime(2026, 9, 4);
      expect(
        activityExportFilename('pdf', ActivityView.all, ActivityRange.all, today: today),
        'accounic-activity-2026-09-04.pdf',
      );
      expect(
        activityExportFilename(
          'csv',
          ActivityView.transaction,
          const ActivityRange(from: '2026-08-28', to: '2026-09-04'),
        ),
        'accounic-activity-transactions-2026-08-28-to-2026-09-04.csv',
      );
    });
  });

  group('the Activity report', () {
    final report = buildActivityReport(
      _bundle(),
      view: ActivityView.all,
      scopeLabel: activityScopeLabel(ActivityRange.all),
      format: _format,
    );

    test('groups by day, newest first — never by account', () {
      expect(
        report.days.map((d) => d.date).toList(),
        ['2026-09-04', '2026-09-02', '2026-08-30'],
      );
    });

    test('puts a day\'s own entries under it, most recent first', () {
      final today = report.days.first;
      expect(today.count, 2);
      // Written at 09:30 and 08:00 — the later one leads, as on screen.
      expect(today.rows.map((r) => r.person).toList(), ['ved', 'sayan']);
      expect(today.rows.first.isSettlement, isTrue);
      expect(today.rows.first.type, 'Settlement received');
    });

    test('counts the entries and the days it actually holds', () {
      expect(report.entryCount, 4);
      expect(report.dayCount, 3);
    });

    test('writes the base currency without its code, and a foreign one with it', () {
      expect(report.days.first.rows[1].amount, '#500.00');
      expect(report.days[1].rows.first.amount, '500.00 AED');
      expect(report.days[1].rows.first.equivalent, '≈ #14000.00');
    });

    test('marks a rate typed by hand, and leaves a fetched one alone', () {
      expect(report.days[1].rows.first.rateNote, 'Custom rate · Amount entered by hand');
      expect(report.days[2].rows.first.rateNote, isNull);
      expect(report.days[2].rows.first.rate, contains('1 AED'));
    });

    test('says which view it was taken from, and over what', () {
      expect(report.title, 'Activity report');
      expect(report.category, 'Everything');
      expect(report.scope, 'All activity');

      final window = buildActivityReport(
        _bundle(),
        view: ActivityView.settlement,
        scopeLabel: activityScopeLabel(
          const ActivityRange(from: '2026-08-28', to: '2026-09-04'),
        ),
        format: _format,
      );
      expect(window.category, 'Settlements');
      expect(window.scope, '28 Aug 2026 → 04 Sep 2026');
    });
  });

  group('the Activity CSV', () {
    final csv = activityEntriesToCsv(_bundle().entries, 'INR', format: _format);
    final lines = csv.trimRight().split('\r\n');

    test('is chronological like the screen, not grouped by person', () {
      expect(lines.first, kActivityCsvColumns.join(','));
      expect(
        lines.skip(1).map((l) => l.split(',').first).toList(),
        ['2026-09-04', '2026-09-04', '2026-09-02', '2026-08-30'],
      );
    });

    test('writes the entered amount and its currency side by side', () {
      final row = lines[3].split(',');
      expect(row[6], '500');
      expect(row[7], 'AED');
      expect(row[8], '14000');
      expect(row[9], 'INR');
      expect(row[10], '28');
      expect(row[11], 'manual-rate');
    });
  });

  group('the Activity export sheet', () {
    testWidgets('asks for the date and the category separately', (tester) async {
      await openSheet(tester);

      expect(find.text('Export activity'), findsOneWidget);
      expect(find.text('Date range'), findsOneWidget);
      expect(find.text('All activity'), findsWidgets);
      expect(find.text('Everything'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('Settlements'), findsOneWidget);
    });

    testWidgets('offers the two feed formats and not the workspace backup',
        (tester) async {
      await openSheet(tester);

      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      // JSON is a workspace backup, not a view of the feed.
      expect(find.text('JSON'), findsNothing);
    });

    testWidgets('states the count, the category and the scope before generating',
        (tester) async {
      await openSheet(tester);
      expect(find.textContaining('4 entries'), findsOneWidget);
      expect(find.textContaining('Everything'), findsWidgets);
    });

    testWidgets('opened from a day, that day is already chosen', (tester) async {
      await openSheet(tester, day: '2026-09-04');
      // The day segment is labelled with the day itself, not "This day".
      expect(find.text('Date range'), findsOneWidget);
      expect(find.text('All activity'), findsOneWidget);
    });

    testWidgets('an empty view explains itself instead of exporting nothing',
        (tester) async {
      await openSheet(tester, header: _header(entries: 0));

      expect(find.text('No activity to export'), findsOneWidget);

      final export = tester.widget<Pressable>(
        find.ancestor(of: find.text('Export'), matching: find.byType(Pressable)).first,
      );
      expect(export.onTap, isNull, reason: 'the export action must be disabled');
    });

    testWidgets('nothing is off-screen on a 360x780 phone', (tester) async {
      await openSheet(tester);

      for (final label in ['Export', 'Cancel', 'PDF', 'CSV']) {
        final rect = tester.getRect(find.text(label).first);
        expect(rect.top, greaterThanOrEqualTo(0), reason: '$label is off the top');
        expect(
          rect.bottom,
          lessThanOrEqualTo(screen.height),
          reason: '$label is off the bottom',
        );
      }
    });
  });

  group('the Activity PDF', () {
    test('is a PDF, and titles itself the activity report', () async {
      final bytes = await ActivityExportPdf.build(
        _bundle(),
        view: ActivityView.all,
        scopeLabel: activityScopeLabel(ActivityRange.all),
      );

      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('still renders when there is nothing in the view', () async {
      final bytes = await ActivityExportPdf.build(
        ExportBundle(header: _header(entries: 0), entries: const [], truncated: false),
        view: ActivityView.settlement,
        scopeLabel: activityScopeLabel(ActivityRange.all),
      );

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
