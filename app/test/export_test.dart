import 'dart:convert';

import 'package:accounic/core/export_csv.dart';
import 'package:accounic/core/export_json.dart';
import 'package:accounic/data/export_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two machine-readable exports (milestone 1.9.0, Phase 5).
///
/// The mirror of web/src/lib/export/csv.test.ts. Both clients have to produce
/// the same file: a user reconciling a phone export against a browser export
/// should find nothing to reconcile.
Map<String, dynamic> _entryJson({
  String id = '11111111-1111-1111-1111-111111111111',
  String kind = 'transaction',
  String scope = 'regular',
  String? note = 'rent',
  String entryCurrency = 'AED',
  int entryAmountMinor = 2000,
  int? rateE9 = 24000000000,
  String? personName = 'VED',
}) => {
  'id': id,
  'kind': kind,
  'type': kind == 'settlement' ? null : 'credit',
  'direction': 'in',
  'date': '2026-08-30',
  'person_id': '22222222-2222-2222-2222-222222222222',
  'person_name': personName,
  'note': note,
  'is_void': false,
  'scope': scope,
  'opening_role': null,
  'transfer_id': null,
  'transfer_role': null,
  'entry_amount_minor': entryAmountMinor,
  'entry_currency': entryCurrency,
  'amount_minor': 48000,
  'ledger_currency': 'INR',
  'amount_base_minor': 48000,
  'base_currency': 'INR',
  'exchange_rate_e9': rateE9,
  'exchange_rate_source': 'open.er-api.com',
  'exchange_rate_at': '2026-08-30T00:00:00Z',
  'conversion_mode': 'automatic',
  'settled_minor': 0,
  'remaining_minor': 48000,
  'settlement_status': 'open',
  'created_at': '2026-08-30T09:12:00Z',
};

ExportEntry _entry({
  String id = '11111111-1111-1111-1111-111111111111',
  String kind = 'transaction',
  String scope = 'regular',
  String? note = 'rent',
  String entryCurrency = 'AED',
  int entryAmountMinor = 2000,
  int? rateE9 = 24000000000,
}) => ExportEntry.fromJson(
  _entryJson(
    id: id,
    kind: kind,
    scope: scope,
    note: note,
    entryCurrency: entryCurrency,
    entryAmountMinor: entryAmountMinor,
    rateE9: rateE9,
  ),
);

ExportHeader _header() => ExportHeader.fromJson({
  'schema_version': 1,
  'generator': 'accounic',
  'exported_at': '2026-09-01T10:00:00Z',
  'filters': {'scope': 'all', 'include_void': false},
  'workspace': {
    'owner_id': '33333333-3333-3333-3333-333333333333',
    'name': 'Export Tester',
    'business_name': null,
    'email': 'owner@example.com',
    'base_currency': 'INR',
  },
  'summary': {'net_position': 48000},
  'currencies': [
    {'code': 'INR', 'name': 'Indian Rupee', 'symbol': '₹', 'decimals': 2},
  ],
  'people': <Map<String, dynamic>>[],
  'counts': {'people': 1, 'entries': 1, 'transactions': 1},
});

void main() {
  group('csvField — RFC 4180 escaping', () {
    test('leaves an ordinary value alone', () {
      expect(csvField('rent'), 'rent');
      expect(csvField(48000), '48000');
      expect(csvField(true), 'true');
    });

    test('writes null as empty, not as the word', () {
      expect(csvField(null), '');
    });

    test('quotes a comma, so one field does not become two', () {
      expect(csvField('rent, August'), '"rent, August"');
    });

    test('doubles a quote inside a quoted field', () {
      expect(csvField('the "final" instalment'), '"the ""final"" instalment"');
    });

    test('quotes a newline, so one row does not become two', () {
      expect(csvField('first line\nsecond line'), '"first line\nsecond line"');
      expect(csvField('with\r\ncrlf'), '"with\r\ncrlf"');
    });

    test('quotes leading and trailing space, which a reader would trim', () {
      expect(csvField('  padded  '), '"  padded  "');
    });

    test('leaves Unicode exactly as it is', () {
      expect(csvField('वेद चौहान'), 'वेद चौहान');
      expect(csvField('عبد الله'), 'عبد الله');
      expect(csvField('日本の取引'), '日本の取引');
    });

    test('quotes a Unicode value that also contains a delimiter', () {
      expect(csvField('वेद, चौहान'), '"वेद, चौहान"');
    });
  });

  group('entriesToCsv', () {
    test('writes the header row first, in the declared order', () {
      expect(entriesToCsv([]).split('\r\n').first, kCsvColumns.join(','));
    });

    test('ends every line with CRLF, including the last', () {
      expect(entriesToCsv([_entry()]).endsWith('\r\n'), isTrue);
    });

    test('states the amount as entered and as an integer, never collapsing currency', () {
      final row = entriesToCsv([_entry()]).split('\r\n')[1].split(',');
      expect(row[kCsvColumns.indexOf('currency')], 'AED');
      expect(row[kCsvColumns.indexOf('amount')], '20');
      expect(row[kCsvColumns.indexOf('amount_minor')], '2000');
      expect(row[kCsvColumns.indexOf('ledger_currency')], 'INR');
      expect(row[kCsvColumns.indexOf('ledger_amount')], '480');
      expect(row[kCsvColumns.indexOf('base_amount_minor')], '48000');
    });

    test('renders a yen amount with no minor unit and a dinar with three', () {
      final yen = entriesToCsv([
        _entry(entryCurrency: 'JPY', entryAmountMinor: 5000),
      ]).split('\r\n')[1].split(',');
      final dinar = entriesToCsv([
        _entry(entryCurrency: 'KWD', entryAmountMinor: 5000),
      ]).split('\r\n')[1].split(',');

      expect(yen[kCsvColumns.indexOf('amount')], '5000');
      expect(dinar[kCsvColumns.indexOf('amount')], '5');
    });

    test('writes the stored rate at full precision, trailing zeros trimmed', () {
      final row = entriesToCsv([_entry(rateE9: 23912345678)]).split('\r\n')[1].split(',');
      expect(row[kCsvColumns.indexOf('exchange_rate')], '23.912345678');
    });

    test('keeps a note with a comma, a quote and a newline in one field', () {
      final csv = entriesToCsv([_entry(note: 'part "final", see\nnote')]);
      expect(csv.contains('"part ""final"", see\nnote"'), isTrue);
      expect(csv.split('\r\n').length, 3);
    });

    test('adds a BOM when asked, and only then', () {
      final csv = entriesToCsv([]);
      expect(csv.codeUnitAt(0), isNot(0xFEFF));
      expect(csvWithBom(csv).codeUnitAt(0), 0xFEFF);
    });

    test('the columns are the same list the web client writes', () {
      // web/src/lib/export/csv.ts carries this order; a difference here means
      // the phone and the browser produce different files.
      expect(kCsvColumns.first, 'entry_id');
      expect(kCsvColumns.last, 'created_at');
      expect(kCsvColumns.length, 28);
    });
  });

  group('the JSON backup', () {
    ExportBundle bundle({bool truncated = false}) => ExportBundle(
      header: _header(),
      entries: [
        _entry(id: 'a', scope: 'opening'),
        _entry(id: 'b'),
        _entry(id: 'c', kind: 'settlement'),
      ],
      truncated: truncated,
    );

    test('leads with its schema version', () {
      final document = buildExportDocument(bundle());
      expect(document.keys.first, 'schema_version');
      expect(document['schema_version'], 1);
    });

    test('keeps the three books apart rather than shipping one flat feed', () {
      final document = buildExportDocument(bundle());
      expect((document['opening_balances'] as List).map((e) => e['id']), ['a']);
      expect((document['transactions'] as List).map((e) => e['id']), ['b']);
      expect((document['settlements'] as List).map((e) => e['id']), ['c']);
    });

    test('defines every currency it uses, exponent included', () {
      final currencies = buildExportDocument(bundle())['currencies'] as List;
      expect(currencies.first['code'], 'INR');
      expect(currencies.first['decimals'], 2);
    });

    test('says outright when it is not the whole workspace', () {
      expect(buildExportDocument(bundle(truncated: true))['truncated'], isTrue);
      expect(buildExportDocument(bundle())['truncated'], isFalse);
    });

    test('carries no key, token or password anywhere in it', () {
      final text = jsonEncode(buildExportDocument(bundle()));
      expect(
        RegExp(r'password|secret|token|service_role|anon_key|jwt', caseSensitive: false)
            .hasMatch(text),
        isFalse,
      );
    });

    test('is valid JSON, indented, and ends with a newline', () {
      final text = exportDocumentToJson(buildExportDocument(bundle()));
      expect(text.endsWith('\n'), isTrue);
      expect(jsonDecode(text)['schema_version'], 1);
    });

    test('names the file after what is in it, and dates it', () {
      final date = DateTime.utc(2026, 9, 1);
      expect(exportFilename('csv', date: date), 'accounic-export-2026-09-01.csv');
      expect(
        exportFilename('json', scope: 'VED Kumar', date: date),
        'accounic-ved-kumar-2026-09-01.json',
      );
    });
  });

  group('the filter contract', () {
    test('sends exactly the parameters the RPC declares', () {
      const filters = ExportFilters(
        from: '2026-01-01',
        to: '2026-09-01',
        currency: 'AED',
        kinds: ['credit'],
        scope: 'regular',
        includeVoid: true,
      );

      expect(filters.toParams(), {
        'p_from': '2026-01-01',
        'p_to': '2026-09-01',
        'p_person_id': null,
        'p_currency': 'AED',
        'p_kinds': ['credit'],
        'p_scope': 'regular',
        'p_include_void': true,
      });
    });

    test('an empty kind list is sent as null, not as an empty array', () {
      const filters = ExportFilters(kinds: []);
      expect(filters.toParams()['p_kinds'], isNull);
    });

    test('describes itself in words before anything is generated', () {
      expect(const ExportFilters().description, 'Everything');
      expect(
        const ExportFilters(from: '2026-01-01', currency: 'AED').description,
        contains('entered in AED'),
      );
      expect(
        const ExportFilters(scope: 'opening').description,
        'opening balances only',
      );
    });
  });
}
