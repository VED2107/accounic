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

  Map<String, dynamic> currencyRow(String code, int net) => {
        'currency': code,
        'total_receivable': net > 0 ? net : 0,
        'total_payable': net < 0 ? -net : 0,
        'net_position': net,
        'gross_credit': net.abs(),
        'gross_debit': 0,
        'gross_settled': 0,
        'people_with_balance': 1,
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
    expect(data.totalsByCurrency[1].totalReceivable, 25000);
    expect(data.totalsByCurrency[2].totalPayable, 4000);
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
