import 'package:flutter_test/flutter_test.dart';

import 'package:accounic/data/models.dart';

/// The opening balance is its own thing (upgrade 46, db/migrations/0019).
///
/// `person_page()` now serves it in its own key and leaves it out of the
/// timeline. These tests pin the client half of that: the model reads the new
/// key, and — the part that matters for anyone still on an older database —
/// falls back to rendering exactly what it always did rather than throwing.
void main() {
  Map<String, dynamic> page({
    Map<String, dynamic>? opening,
    List<Map<String, dynamic>> timeline = const [],
    List<Map<String, dynamic>>? openingHistory,
    int openingMinor = 0,
    int netBalance = 0,
    bool includeOpeningKeys = true,
  }) {
    return {
      'person': {
        'id': 'p1',
        'owner_id': 'o1',
        'name': 'Sayan Roy',
        'type': 'person',
        'is_archived': false,
      },
      'balance': {
        'person_id': 'p1',
        'owner_id': 'o1',
        'name': 'Sayan Roy',
        'type': 'person',
        'is_archived': false,
        'currency': 'INR',
        'base_currency': 'INR',
        'total_credit': 0,
        'total_debit': 0,
        'settled_in': 0,
        'settled_out': 0,
        'total_settled': 0,
        'outstanding_receivable': 0,
        'outstanding_payable': 0,
        'net_balance': netBalance,
        'transaction_count': timeline.length,
        'opening_minor': openingMinor,
      },
      'currency': 'INR',
      'default_currency': 'INR',
      'base_currency': 'INR',
      if (includeOpeningKeys) 'opening': opening,
      if (includeOpeningKeys) 'opening_history': openingHistory ?? const [],
      'timeline': timeline,
      'timeline_total': timeline.length,
      'open_transactions': const [],
    };
  }

  final aedOpening = {
    'person_id': 'p1',
    'owner_id': 'o1',
    'transaction_id': 'op1',
    'entry_type': 'credit',
    'signed_minor': 1039369,
    'amount_minor': 1039369,
    'ledger_currency': 'INR',
    'entry_amount_minor': 40000,
    'entry_currency': 'AED',
    'amount_base_minor': 1039369,
    'base_currency': 'INR',
    'entered_amount_minor': 40000,
    'entered_currency': 'AED',
    'exchange_rate_e9': 25984225000,
    'exchange_rate_source': 'open.er-api.com',
    'conversion_mode': 'automatic',
    'entry_date': '2026-08-20',
    'created_at': '2026-08-20T10:00:00.000Z',
    'note': 'Opening balance',
  };

  test('the opening balance arrives in its own section', () {
    final parsed = PersonPage.fromJson(
      page(opening: aedOpening, openingMinor: 1039369, netBalance: 1039369),
    );

    expect(parsed.opening, isNotNull);
    expect(parsed.opening!.transactionId, 'op1');
    // The original figure, in the currency it was stated in — 400 AED — with
    // the rupee equivalent beside it rather than in place of it.
    expect(parsed.opening!.entryAmountMinor, 40000);
    expect(parsed.opening!.entryCurrency, 'AED');
    expect(parsed.opening!.amountMinor, 1039369);
    expect(parsed.opening!.ledgerCurrency, 'INR');
    expect(parsed.opening!.amountBaseMinor, 1039369);
    expect(parsed.opening!.isReceivable, isTrue);
  });

  test('and is not one of the timeline rows', () {
    final parsed = PersonPage.fromJson(
      page(
        opening: aedOpening,
        openingMinor: 1039369,
        netBalance: 1139369,
        timeline: [
          {
            'id': 'e1',
            'entry_kind': 'transaction',
            'entry_type': 'credit',
            'money_direction': 'in',
            'amount_minor': 100000,
            'entry_date': '2026-08-22',
            'is_void': false,
          },
        ],
      ),
    );

    expect(parsed.timeline, hasLength(1));
    expect(parsed.timeline.every((entry) => !entry.isOpening), isTrue);
  });

  test('but it still counts towards the position', () {
    final parsed = PersonPage.fromJson(
      page(opening: aedOpening, openingMinor: 1039369, netBalance: 1139369),
    );
    // 1,039.369 of opening plus 1,000 of entries. The balance is the
    // database's; this asserts the client did not quietly drop the opening
    // figure when it moved out of the timeline.
    expect(parsed.balance.openingMinor, 1039369);
    expect(parsed.balance.netBalance, 1139369);
  });

  test('the opening balance carries its own settlement state', () {
    // Its own section, its own settle action, its own remainder — separate from
    // the regular transactions' settle path (db/migrations/0021).
    final parsed = PersonPage.fromJson(
      page(
        opening: {...aedOpening, 'settled_minor': 400000, 'remaining_minor': 639369,
          'status': 'partial'},
        openingMinor: 1039369,
        netBalance: 639369,
      ),
    );

    expect(parsed.opening!.settledMinor, 400000);
    expect(parsed.opening!.remainingMinor, 639369);
    expect(parsed.opening!.status, SettlementStatus.partial);
    expect(parsed.opening!.isOutstanding, isTrue);
  });

  test('a fully settled opening balance offers nothing more to settle', () {
    final parsed = PersonPage.fromJson(
      page(
        opening: {...aedOpening, 'settled_minor': 1039369, 'remaining_minor': 0,
          'status': 'settled'},
        openingMinor: 1039369,
        netBalance: 0,
      ),
    );

    expect(parsed.opening!.isOutstanding, isFalse);
    expect(parsed.opening!.status, SettlementStatus.settled);
    // Settling is not editing: the opening balance itself is untouched.
    expect(parsed.opening!.entryAmountMinor, 40000);
    expect(parsed.balance.openingMinor, 1039369);
  });

  test('against a database older than 0021 nothing is settled and all is left', () {
    final parsed = PersonPage.fromJson(
      page(opening: aedOpening, openingMinor: 1039369, netBalance: 1039369),
    );
    expect(parsed.opening!.settledMinor, 0);
    expect(parsed.opening!.remainingMinor, parsed.opening!.amountMinor);
    expect(parsed.opening!.isOutstanding, isTrue);
  });

  test('an account with no opening balance says so rather than showing zero', () {
    final parsed = PersonPage.fromJson(page(opening: null));
    expect(parsed.opening, isNull);
    expect(parsed.balance.openingMinor, 0);
  });

  test('replaced opening balances are kept, and affect nothing', () {
    final parsed = PersonPage.fromJson(
      page(
        opening: aedOpening,
        openingMinor: 1039369,
        netBalance: 1039369,
        openingHistory: [
          {
            ...aedOpening,
            'transaction_id': 'op0',
            'entry_amount_minor': 750000,
            'entry_currency': 'INR',
            'amount_minor': 750000,
          },
        ],
      ),
    );

    expect(parsed.openingHistory, hasLength(1));
    expect(parsed.openingHistory.first.entryAmountMinor, 750000);
    // The live one is still the live one.
    expect(parsed.opening!.transactionId, 'op1');
  });

  test('a database older than 0019 still renders', () {
    // No `opening` key at all: every entry, opening balance included, is still
    // in the timeline, and the screen shows what it always showed rather than
    // throwing on a missing key.
    final parsed = PersonPage.fromJson(
      page(
        includeOpeningKeys: false,
        openingMinor: 400000,
        netBalance: 400000,
        timeline: [
          {
            'id': 'op1',
            'entry_kind': 'transaction',
            'entry_type': 'credit',
            'money_direction': 'in',
            'amount_minor': 400000,
            'entry_date': '2026-08-20',
            'is_void': false,
            'is_opening': true,
          },
        ],
      ),
    );

    expect(parsed.opening, isNull);
    expect(parsed.openingHistory, isEmpty);
    expect(parsed.timeline.single.isOpening, isTrue);
    expect(parsed.timeline.single.label, 'Opening balance');
  });
}
