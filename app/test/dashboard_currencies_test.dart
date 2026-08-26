import 'package:accounic/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dashboard's per-currency totals (db/migrations/0015).
///
/// The rule these pin is that nothing is ever added across currencies. The
/// base-currency headline stays exactly what it was — it is the only figure
/// allowed to mix them, and only because it converts first — while every row in
/// `totals_by_currency` is that currency's own money and nothing else.
void main() {
  Map<String, dynamic> dashboardJson({
    List<Map<String, dynamic>>? totals,
    List<Map<String, dynamic>>? today,
  }) =>
      {
        'profile': {'name': 'Ved', 'currency': 'INR'},
        'base_currency': 'INR',
        'summary': {
          'total_receivable': 500000,
          'total_payable': 120000,
          'net_position': 380000,
          'people_with_balance': 3,
          'people_count': 4,
          'base_currency': 'INR',
          'currency_count': 3,
          'unconverted_people': 0,
        },
        'today': {'credit': 1000, 'debit': 0, 'settled': 0, 'count': 1},
        if (totals != null) 'totals_by_currency': totals,
        if (today != null) 'today_by_currency': today,
        'recent_activity': [],
        'people_with_balance': [],
      };

  /// One row of totals_by_currency as db/migrations/0017 builds it: the money
  /// in [code], plus what that is worth in the base currency.
  Map<String, dynamic> currencyRow(String code, int net, {int? baseEquivalent}) => {
        'currency': code,
        'base_currency': 'INR',
        'net_position': net,
        'net_base_minor': baseEquivalent ?? (code == 'INR' ? net : null),
        'gross_credit': net > 0 ? net : 0,
        'gross_debit': net < 0 ? -net : 0,
        'gross_settled': 0,
        'entry_count': 1,
        'people_count': 1,
      };

  test('every currency with entries comes through, base included', () {
    final data = Dashboard.fromJson(dashboardJson(
      totals: [
        currencyRow('INR', 380000),
        currencyRow('USD', 25000),
        currencyRow('AED', -4000),
      ],
    ));

    expect(data.totalsByCurrency.map((r) => r.currency), ['INR', 'USD', 'AED']);
    // INR is a row like any other, not just the headline it also feeds.
    expect(data.totalsByCurrency.first.netPosition, 380000);
    expect(data.totalsByCurrency[1].grossCredit, 25000);
    expect(data.totalsByCurrency[2].grossDebit, 4000);
  });

  test('a foreign row keeps its own money and carries an equivalent', () {
    final data = Dashboard.fromJson(dashboardJson(totals: [
      currencyRow('INR', 500000),
      // USD 100, worth ₹9,542 at the moment it was read.
      currencyRow('USD', 10000, baseEquivalent: 954200),
    ]));

    final usd = data.totalsByCurrency.firstWhere((r) => r.currency == 'USD');
    // The primary figure is dollars and stays dollars.
    expect(usd.netPosition, 10000);
    expect(usd.currency, 'USD');
    // The rupee figure is beside it, not instead of it.
    expect(usd.netBaseMinor, 954200);
    expect(usd.baseCurrency, 'INR');
    expect(usd.showsBaseEquivalent, isTrue);

    // The base currency needs no equivalent of itself.
    final inr = data.totalsByCurrency.firstWhere((r) => r.currency == 'INR');
    expect(inr.showsBaseEquivalent, isFalse);
  });

  test('an activity row reports what was entered, not the conversion', () {
    // A USD 100 entry against a RUPEE-denominated person: amount_minor is the
    // converted ₹9,542 and entry_amount_minor is the $100 that was typed. The
    // bug this pins was reporting the first as the amount.
    final item = ActivityItem.fromJson({
      'id': 't1',
      'person_id': 'p1',
      'person_name': 'SAYAN',
      'entry_kind': 'transaction',
      'entry_type': 'credit',
      'amount_minor': 954200,
      'currency': 'INR',
      'entry_amount_minor': 10000,
      'entry_currency': 'USD',
      'amount_base_minor': 954200,
      'base_currency': 'INR',
      'entered_amount_minor': 10000,
      'entered_currency': 'USD',
      'entry_date': '2026-08-27',
    });

    expect(item.entryAmountMinor, 10000);
    expect(item.entryCurrency, 'USD');
    expect(item.amountMinor, 954200);      // the ledger figure is still there
    expect(item.showsBaseEquivalent, isTrue);
  });

  test('an entry needing no conversion shows one figure only', () {
    final item = ActivityItem.fromJson({
      'id': 't2',
      'person_id': 'p1',
      'person_name': 'SAYAN',
      'entry_kind': 'transaction',
      'entry_type': 'credit',
      'amount_minor': 500000,
      'currency': 'INR',
      'entry_amount_minor': 500000,
      'entry_currency': 'INR',
      'amount_base_minor': 500000,
      'base_currency': 'INR',
      'entry_date': '2026-08-27',
    });

    expect(item.entryCurrency, 'INR');
    expect(item.entryAmountMinor, 500000);
    // Nothing to add: "≈ ₹5,000" under "₹5,000" is noise.
    expect(item.showsBaseEquivalent, isFalse);
  });

  test('an older database without 0017 still renders', () {
    // entry_* absent: fall back to the ledger pair, which is what the two were
    // before the columns existed.
    final item = ActivityItem.fromJson({
      'id': 't3',
      'person_id': 'p1',
      'person_name': 'SAYAN',
      'entry_kind': 'transaction',
      'entry_type': 'credit',
      'amount_minor': 500000,
      'currency': 'AED',
      'entry_date': '2026-08-27',
    });

    expect(item.entryAmountMinor, 500000);
    expect(item.entryCurrency, 'AED');
    expect(item.showsBaseEquivalent, isFalse);
  });

  test('the base-currency headline is untouched by the breakdown', () {
    final data = Dashboard.fromJson(dashboardJson(
      totals: [currencyRow('INR', 380000), currencyRow('USD', 25000)],
    ));

    // 380000 + 25000 would be the bug: rupees and dollars added together. The
    // headline stays the converted figure the engine produced.
    expect(data.summary.netPosition, 380000);
    expect(data.currency, 'INR');
  });

  test('an empty workspace has no currency rows rather than zeroed ones', () {
    final data = Dashboard.fromJson(dashboardJson(totals: []));
    expect(data.totalsByCurrency, isEmpty);
    expect(data.todayByCurrency, isEmpty);
  });

  test('a database without 0015 reads as no breakdown, not as a crash', () {
    final data = Dashboard.fromJson(dashboardJson());
    expect(data.totalsByCurrency, isEmpty);
    expect(data.todayByCurrency, isEmpty);
    expect(data.summary.netPosition, 380000);
  });

  test("today's movement keeps each currency's own amount", () {
    final data = Dashboard.fromJson(dashboardJson(
      totals: [currencyRow('INR', 380000), currencyRow('USD', 25000)],
      today: [
        {'currency': 'INR', 'credit': 100000, 'debit': 0, 'settled': 0, 'count': 1},
        {'currency': 'USD', 'credit': 10000, 'debit': 0, 'settled': 5000, 'count': 2},
      ],
    ));

    final usd = data.todayByCurrency.firstWhere((r) => r.currency == 'USD');
    // USD 100 stays USD 100 — it is not folded into the rupee figure.
    expect(usd.credit, 10000);
    expect(usd.moved, 15000);
    expect(data.todayByCurrency.first.moved, 100000);
  });
}
