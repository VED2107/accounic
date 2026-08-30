import 'package:accounic/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dashboard leads with the currency the money was entered in
/// (db/migrations/0024).
///
/// `db/tests/12_dashboard_currency_breakdown.sql` proves the figures against
/// real rows. These pin the half the Flutter client owns: that it parses the
/// `cash` / `opening` objects on each `totals_by_currency` row, that the
/// primary figure is the ORIGINAL entered amount, that the base-currency
/// equivalent is reference only, and that the rows order INR-first.
void main() {
  Map<String, dynamic> half(
    String code, {
    required int credit,
    int debit = 0,
    int settled = 0,
    int? netBase,
    int today = 0,
    int entryCount = 1,
    int? peopleCount,
  }) {
    final receivable = (credit - settled).clamp(0, 1 << 62);
    final payable = debit;
    return {
      'currency': code,
      'base_currency': 'INR',
      'credit': credit,
      'debit': debit,
      'settled': settled,
      'receivable': receivable,
      'payable': payable,
      'net': receivable - payable,
      'net_base_minor': netBase,
      'today': today,
      'today_count': today == 0 ? 0 : 1,
      'entry_count': entryCount,
      if (peopleCount != null) 'people_count': peopleCount,
    };
  }

  Map<String, dynamic> row(
    String code, {
    Map<String, dynamic>? cash,
    Map<String, dynamic>? opening,
  }) =>
      {
        'currency': code,
        'base_currency': 'INR',
        'net_position': 0,
        'cash_net_position': 0,
        'opening_net_position': 0,
        'net_base_minor': code == 'INR' ? 0 : null,
        'gross_credit': 0,
        'gross_debit': 0,
        'gross_settled': 0,
        'entry_count': 0,
        'people_count': 0,
        if (cash != null) 'cash': cash,
        if (opening != null) 'opening': opening,
      };

  Map<String, dynamic> dashboardJson(List<Map<String, dynamic>> totals) => {
        'profile': {'name': 'Ved', 'currency': 'INR'},
        'base_currency': 'INR',
        'summary': {
          'total_receivable': 0,
          'total_payable': 0,
          'net_position': 700000,
          'people_with_balance': 2,
          'people_count': 2,
          'base_currency': 'INR',
          'currency_count': 2,
          'unconverted_people': 0,
        },
        'today': {'credit': 0, 'debit': 0, 'settled': 0, 'count': 0},
        'cash_in_hand': {'base_currency': 'INR', 'position': 544000},
        'opening': {'base_currency': 'INR', 'position': 660000},
        'totals_by_currency': totals,
        'recent_activity': [],
        'people_with_balance': [],
      };

  test('parses the per-currency cash and opening breakdown from 0024', () {
    final data = Dashboard.fromJson(dashboardJson([
      row('INR',
          cash: half('INR', credit: 400000, entryCount: 2, peopleCount: 2),
          opening: half('INR', credit: 300000, entryCount: 2, peopleCount: 2)),
      row('AED',
          cash: half('AED', credit: 6000, netBase: 144000, entryCount: 2, peopleCount: 2),
          opening: half('AED', credit: 15000, netBase: 360000, entryCount: 2, peopleCount: 2)),
    ]));

    final aed = data.totalsByCurrency.firstWhere((r) => r.currency == 'AED');

    // 20 AED + 40 AED = 60 AED, entered — never an INR figure reconverted.
    expect(aed.cash!.credit, 6000);
    expect(aed.cash!.net, 6000);
    expect(aed.cash!.currency, 'AED');
    // The rupee figure is beside it, not instead of it.
    expect(aed.cash!.netBaseMinor, 144000);
    expect(aed.cash!.showsBaseEquivalent, isTrue);

    // The opening 150 AED is its own half and is NOT in cash in hand.
    expect(aed.opening!.credit, 15000);
    expect(aed.cash!.credit, isNot(equals(aed.opening!.credit)));

    // INR carries no equivalent of itself.
    final inr = data.totalsByCurrency.firstWhere((r) => r.currency == 'INR');
    expect(inr.cash!.showsBaseEquivalent, isFalse);
    expect(inr.cash!.credit, 400000);
  });

  test('a database without 0024 leaves cash and opening null, no crash', () {
    final data = Dashboard.fromJson(dashboardJson([row('INR'), row('USD')]));
    expect(data.totalsByCurrency, hasLength(2));
    expect(data.totalsByCurrency.first.cash, isNull);
    expect(data.totalsByCurrency.first.opening, isNull);
    expect(data.summary.netPosition, 700000);
  });

  test('CurrencyHalfBreakdown.order: base currency first, then alphabetical', () {
    final rows = [
      CurrencyHalfBreakdown.fromJson(half('USD', credit: 5000)),
      CurrencyHalfBreakdown.fromJson(half('AED', credit: 6000)),
      CurrencyHalfBreakdown.fromJson(half('INR', credit: 400000)),
      CurrencyHalfBreakdown.fromJson(half('EUR', credit: 7000)),
    ];
    expect(
      CurrencyHalfBreakdown.order(rows, 'INR').map((r) => r.currency),
      ['INR', 'AED', 'EUR', 'USD'],
    );
  });

  test('CurrencyHalfBreakdown.order drops currencies with no data', () {
    final rows = [
      CurrencyHalfBreakdown.fromJson(half('INR', credit: 0)),
      CurrencyHalfBreakdown.fromJson(half('AED', credit: 6000)),
      CurrencyHalfBreakdown.fromJson(half('USD', credit: 0)),
    ];
    expect(
      CurrencyHalfBreakdown.order(rows, 'INR').map((r) => r.currency),
      ['AED'],
    );
  });

  test('person page carries regular_by_currency and opening_by_currency', () {
    final page = PersonPage.fromJson({
      'person': {
        'id': 'p1',
        'owner_id': 'o1',
        'name': 'VED',
        'type': 'person',
        'currency': 'INR',
        'is_archived': false,
        'created_at': '2026-08-01T00:00:00Z',
        'updated_at': '2026-08-01T00:00:00Z',
      },
      'balance': {
        'person_id': 'p1',
        'owner_id': 'o1',
        'name': 'VED',
        'type': 'person',
        'currency': 'INR',
        'base_currency': 'INR',
        'total_credit': 148000,
        'total_debit': 0,
        'total_settled': 0,
        'settled_in': 0,
        'settled_out': 0,
        'outstanding_receivable': 148000,
        'outstanding_payable': 0,
        'net_balance': 148000,
        'net_balance_base': 148000,
        'transaction_count': 2,
        'opening_minor': 0,
      },
      'currency': 'INR',
      'default_currency': 'INR',
      'base_currency': 'INR',
      'regular_by_currency': [
        half('INR', credit: 100000, entryCount: 1),
        half('AED', credit: 2000, netBase: 48000, entryCount: 1),
      ],
      'opening_by_currency': [
        half('INR', credit: 200000, entryCount: 1),
        half('AED', credit: 10000, netBase: 240000, entryCount: 1),
      ],
      'timeline': [],
      'timeline_total': 2,
      'open_transactions': [],
    });

    expect(page.regularByCurrency.map((r) => r.currency), ['INR', 'AED']);
    expect(
      page.regularByCurrency.firstWhere((r) => r.currency == 'AED').net,
      2000,
    );
    expect(
      page.openingByCurrency.firstWhere((r) => r.currency == 'AED').credit,
      10000,
    );
  });
}
