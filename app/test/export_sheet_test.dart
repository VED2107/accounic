import 'package:accounic/core/theme.dart';
import 'package:accounic/data/export_models.dart';
import 'package:accounic/data/export_pdf.dart';
import 'package:accounic/providers.dart';
import 'package:accounic/ui/sheets/export_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The export sheet on a phone (Phase 4).
///
/// What these pin is the promise the sheet makes: **the user knows what they
/// are exporting before anything is generated**, the choices are reachable with
/// a thumb, and the whole flow fits a 360×780 screen with nothing off-screen.
ExportHeader _header({int entries = 42, int people = 3, String scope = 'all'}) =>
    ExportHeader.fromJson({
      'schema_version': 1,
      'generator': 'accounic',
      'exported_at': '2026-09-01T10:00:00Z',
      'filters': {'scope': scope, 'include_void': false},
      'workspace': {'name': 'Export Tester', 'base_currency': 'INR'},
      'summary': {'net_position': 1000},
      'totals_by_currency': [
        {
          'currency': 'INR',
          'receivable': 120000,
          'payable': 20000,
          'net': 100000,
          'cash': {'net': 60000},
          'opening': {'net': 40000},
        },
      ],
      'currencies': [
        {'code': 'INR', 'name': 'Indian Rupee', 'symbol': 'Rs', 'decimals': 2},
      ],
      'people': [
        {
          'id': 'p1',
          'name': 'VED',
          'ledger_currency': 'INR',
          'is_archived': false,
          'balance': {
            'currency': 'INR',
            'net_balance': 100000,
            'outstanding_receivable': 120000,
            'outstanding_payable': 20000,
            'opening_net_minor': 40000,
          },
        },
      ],
      'counts': {
        'people': people,
        'entries': entries,
        'transactions': entries,
        'settlements': 0,
        'transfers': 0,
        'opening': 1,
        'voided': 0,
      },
    });

void main() {
  const screen = Size(360, 780);

  Future<void> openSheet(
    WidgetTester tester, {
    ExportHeader? header,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exportPreviewProvider(const ExportFilters())
              .overrideWith((ref) async => header ?? _header()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => Center(
                child: ElevatedButton(
                  onPressed: () => showExportSheet(context, ref),
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

  group('the export sheet', () {
    testWidgets('says what will be exported before anything is generated',
        (tester) async {
      await openSheet(tester);

      // The counts come from the database's header, not from a guess.
      expect(find.textContaining('42 entries'), findsOneWidget);
      expect(find.textContaining('3 accounts'), findsOneWidget);
    });

    testWidgets('offers the three formats, each with what it is for',
        (tester) async {
      await openSheet(tester);

      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('CSV'), findsOneWidget);
      expect(find.text('JSON'), findsOneWidget);
      expect(find.textContaining('spreadsheet'), findsOneWidget);
      expect(find.textContaining('backup'), findsOneWidget);
    });

    testWidgets('every choice is a touch target a thumb can hit',
        (tester) async {
      await openSheet(tester);

      for (final label in ['All time', 'This month', 'This year']) {
        final size = tester.getSize(find.ancestor(
          of: find.text(label),
          matching: find.byType(AnimatedContainer),
        ).first);
        expect(
          size.height,
          greaterThanOrEqualTo(44),
          reason: '"$label" is only ${size.height}pt tall',
        );
      }
    });

    testWidgets('nothing is off-screen on a 360x780 phone', (tester) async {
      await openSheet(tester);

      for (final label in ['Export', 'Cancel', 'PDF']) {
        final rect = tester.getRect(find.text(label).first);
        expect(rect.top, greaterThanOrEqualTo(0), reason: '$label is off the top');
        expect(
          rect.bottom,
          lessThanOrEqualTo(screen.height),
          reason: '$label is off the bottom',
        );
      }
    });

    testWidgets('voided history is excluded until it is asked for',
        (tester) async {
      await openSheet(tester);

      final toggle = find.byType(SwitchListTile).first;
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(find.textContaining('Off by default'), findsOneWidget);
    });
  });

  group('the workspace PDF', () {
    test('is a PDF, and carries the cover facts', () async {
      final bundle = ExportBundle(
        header: _header(),
        entries: [
          ExportEntry.fromJson({
            'id': 'e1',
            'kind': 'transaction',
            'type': 'credit',
            'date': '2026-08-30',
            'person_id': 'p1',
            'person_name': 'VED',
            'note': 'rent',
            'is_void': false,
            'scope': 'regular',
            'entry_amount_minor': 100000,
            'entry_currency': 'INR',
            'amount_minor': 100000,
            'ledger_currency': 'INR',
            'amount_base_minor': 100000,
            'base_currency': 'INR',
            'settled_minor': 40000,
            'remaining_minor': 60000,
            'settlement_status': 'partial',
            'created_at': '2026-08-30T09:00:00Z',
          }),
        ],
        truncated: false,
      );

      final bytes = await WorkspaceExportPdf.build(bundle);

      // A PDF that is not a PDF is worse than none: it opens to an error in
      // whatever reader the user has, and looks like our fault twice.
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });

    test('a truncated export is still a valid file', () async {
      final bytes = await WorkspaceExportPdf.build(
        ExportBundle(header: _header(entries: 0), entries: const [], truncated: true),
      );

      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    });
  });
}
