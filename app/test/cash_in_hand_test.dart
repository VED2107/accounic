import 'package:accounic/core/statement.dart';
import 'package:accounic/data/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cash in hand, the opening balance, and the crash between them
/// (db/migrations/0022).
///
/// Three things are pinned here, and the first is a real bug that shipped:
///
///   1. THE REGRESSION. Editing an opening balance filled `opening_history` for
///      the first time, and `PersonOpening.fromJson` cast `transaction_id` —
///      a key `opening_history` did not carry — straight to `String`. Every
///      subsequent load of that person threw, and the screen said
///      "That account could not be loaded." The payload below is the real
///      shape `person_page()` served, and parsing it must not throw.
///
///   2. THE SEPARATION. Cash in hand never contains the opening balance, the
///      opening balance is calculated independently, and the two add back to
///      the account position. Nothing is double-counted.
///
///   3. THE SECTIONS. Opening-balance credits, debits and settlements are in
///      `openingActivity` and never in `timeline`.
void main() {
  /// The `opening` payload, exactly as `person_opening` serves it.
  Map<String, dynamic> opening({int amount = 500000, String type = 'debit'}) => {
        'person_id': 'p1',
        'owner_id': 'o1',
        'transaction_id': 't-open',
        'entry_type': type,
        'signed_minor': type == 'credit' ? amount : -amount,
        'amount_minor': amount,
        'ledger_currency': 'INR',
        'entry_amount_minor': amount,
        'entry_currency': 'INR',
        'amount_base_minor': amount,
        'base_currency': 'INR',
        'entered_amount_minor': null,
        'entered_currency': null,
        'exchange_rate_e9': null,
        'exchange_rate_at': null,
        'exchange_rate_source': null,
        'rate_is_manual': false,
        'conversion_mode': null,
        'auto_converted_amount_minor': null,
        'entry_date': '2026-08-28',
        'note': 'Opening balance',
        'created_at': '2026-08-29T07:17:43.888879+00:00',
        'settled_minor': 50000,
        'remaining_minor': amount - 50000,
        'status': 'partial',
      };

  Map<String, dynamic> balance({
    int net = 150000,
    int cash = 600000,
    int openingNet = -450000,
  }) =>
      {
        'person_id': 'p1',
        'name': 'ved',
        'type': 'person',
        'is_archived': false,
        'currency': 'INR',
        'base_currency': 'INR',
        'total_credit': 600000,
        'total_debit': 500000,
        'settled_in': 0,
        'settled_out': 50000,
        'total_settled': 50000,
        'outstanding_receivable': 600000,
        'outstanding_payable': 450000,
        'net_balance': net,
        'net_balance_base': net,
        'transaction_count': 4,
        'opening_minor': -500000,
        'cash_in_hand_minor': cash,
        'cash_in_hand_base': cash,
        'opening_net_minor': openingNet,
        'opening_net_base': openingNet,
        'regular_receivable': 600000,
        'regular_payable': 0,
        'regular_settled_total': 0,
        'regular_credit_minor': 600000,
        'regular_debit_minor': 0,
        'opening_receivable': 0,
        'opening_payable': 450000,
        'opening_settled_total': 50000,
        'opening_credit_minor': 0,
        'opening_debit_minor': 500000,
        'opening_entry_count': 1,
      };

  Map<String, dynamic> page({
    List<Map<String, dynamic>> openingHistory = const [],
    List<Map<String, dynamic>> openingActivity = const [],
    List<Map<String, dynamic>> timeline = const [],
    Map<String, dynamic>? openingRow,
  }) =>
      {
        'person': const {
          'id': 'p1',
          'owner_id': 'o1',
          'name': 'ved',
          'type': 'person',
          'is_archived': false,
          'currency': 'INR',
        },
        'balance': balance(),
        'currency': 'INR',
        'default_currency': 'INR',
        'base_currency': 'INR',
        'opening': openingRow ?? opening(),
        'regular': const {
          'currency': 'INR',
          'base_currency': 'INR',
          'position': 600000,
          'position_base': 600000,
          'receivable': 600000,
          'payable': 0,
          'settled': 0,
          'credit': 600000,
          'debit': 0,
        },
        'opening_position': const {
          'currency': 'INR',
          'base_currency': 'INR',
          'position': -450000,
          'position_base': -450000,
          'receivable': 0,
          'payable': 450000,
          'settled': 50000,
          'credit': 0,
          'debit': 500000,
          'entry_count': 1,
        },
        'opening_history': openingHistory,
        'opening_activity': openingActivity,
        'timeline': timeline,
        'timeline_total': timeline.length,
        'open_transactions': const [],
      };

  group('the regression: editing an opening balance stops the person loading', () {
    test(
        'an opening_history row keyed on `id` alone parses instead of throwing '
        '(the shape that shipped)', () {
      // This is the payload person_page() served BEFORE db/migrations/0022:
      // `id`, and no `transaction_id`. `json[...] as String` on a null threw
      // here, and the person screen reported "That account could not be
      // loaded." on every load from then on.
      final historic = <String, dynamic>{
        'id': 't-old',
        'amount_minor': 50000,
        'entry_type': 'debit',
        'entry_date': '2026-08-28',
        'created_at': '2026-08-28T18:20:54.769979+00:00',
        'entry_amount_minor': 50000,
        'entry_currency': 'INR',
        'ledger_currency': 'INR',
        'amount_base_minor': 50000,
        'base_currency': 'INR',
        'entered_amount_minor': null,
        'entered_currency': null,
        'exchange_rate_e9': null,
        'exchange_rate_source': null,
        'conversion_mode': null,
        'auto_converted_amount_minor': null,
      };

      final parsed = PersonPage.fromJson(page(openingHistory: [historic]));

      expect(parsed.openingHistory, hasLength(1));
      // Falls back to `id`, which is the same row.
      expect(parsed.openingHistory.single.transactionId, 't-old');
      expect(parsed.openingHistory.single.amountMinor, 50000);
    });

    test('and the 0022 payload, which carries transaction_id, parses too', () {
      final modern = <String, dynamic>{
        ...opening(amount: 50000),
        'transaction_id': 't-old',
        'id': 't-old',
        'settled_minor': 0,
        'remaining_minor': 0,
        'status': 'void',
      };

      final parsed = PersonPage.fromJson(page(openingHistory: [modern]));

      expect(parsed.openingHistory.single.transactionId, 't-old');
      expect(parsed.openingHistory.single.entryAmountMinor, 50000);
    });

    test('edit → save → reload → reopen: the page parses every time', () {
      // 1–4: the account before the edit — no history at all, which is why the
      // bug lay hidden until the first edit.
      final before = PersonPage.fromJson(page());
      expect(before.openingHistory, isEmpty);
      expect(before.opening!.amountMinor, 500000);

      // 5: reload after the edit. `opening_history` is now populated, and the
      // opening balance is the new figure.
      final reloaded = PersonPage.fromJson(page(
        openingRow: opening(amount: 750000),
        openingHistory: [
          {...opening(amount: 500000), 'transaction_id': 't-old', 'status': 'void'},
        ],
      ));
      expect(reloaded.opening!.amountMinor, 750000);
      expect(reloaded.openingHistory, hasLength(1));

      // 6: open the person again — the read that used to throw.
      final reopened = PersonPage.fromJson(page(
        openingRow: opening(amount: 750000),
        openingHistory: [
          {...opening(amount: 500000), 'transaction_id': 't-old', 'status': 'void'},
        ],
      ));
      expect(reopened.opening!.amountMinor, 750000);
      expect(reopened.openingHistory.single.transactionId, isNotEmpty);

      // And the regular transactions are untouched by any of it.
      expect(reopened.timeline, isEmpty);
      expect(reopened.regular.positionMinor, before.regular.positionMinor);
    });
  });

  group('cash in hand excludes the opening balance', () {
    test('the two halves add back to the account position', () {
      final parsed = PersonPage.fromJson(page());

      expect(parsed.regular.positionMinor, 600000);
      expect(parsed.openingPosition.positionMinor, -450000);
      expect(
        parsed.regular.positionMinor + parsed.openingPosition.positionMinor,
        parsed.balance.netBalance,
      );
    });

    test('and neither figure is the whole position, so neither is the other', () {
      final parsed = PersonPage.fromJson(page());
      expect(parsed.regular.positionMinor, isNot(parsed.balance.netBalance));
      expect(parsed.openingPosition.positionMinor, isNot(parsed.balance.netBalance));
    });

    test('the balance row carries the same split', () {
      final parsed = PersonBalance.fromJson(balance());
      expect(parsed.cashInHandMinor + parsed.openingNetMinor, parsed.netBalance);
      expect(parsed.regularReceivable, 600000);
      expect(parsed.openingPayable, 450000);
      expect(parsed.hasOpening, isTrue);
    });

    test('an account with no opening balance has cash in hand for its whole '
        'position', () {
      final parsed = PersonBalance.fromJson({
        ...balance(net: 33300, cash: 33300, openingNet: 0),
        'opening_minor': 0,
        'opening_entry_count': 0,
      });

      expect(parsed.cashInHandMinor, parsed.netBalance);
      expect(parsed.openingNetMinor, 0);
      expect(parsed.hasOpening, isFalse);
    });

    test('against a database older than 0022 the whole position is reported as '
        'cash in hand rather than a split it cannot make', () {
      final old = PersonBalance.fromJson(const {
        'person_id': 'p1',
        'name': 'ved',
        'type': 'person',
        'is_archived': false,
        'currency': 'INR',
        'base_currency': 'INR',
        'total_credit': 600000,
        'total_debit': 0,
        'settled_in': 0,
        'settled_out': 0,
        'total_settled': 0,
        'outstanding_receivable': 600000,
        'outstanding_payable': 0,
        'net_balance': 600000,
        'transaction_count': 1,
      });

      expect(old.cashInHandMinor, 600000);
      expect(old.openingNetMinor, 0);
      expect(old.cashInHandMinor + old.openingNetMinor, old.netBalance);
    });
  });

  group('the workspace totals', () {
    test('cash in hand and the opening balance are two separate totals', () {
      final dash = Dashboard.fromJson(const {
        'profile': {'name': 'Ved', 'currency': 'INR'},
        'base_currency': 'INR',
        'summary': {
          'total_receivable': 649900,
          'total_payable': 0,
          'net_position': 699900,
          'people_with_balance': 2,
          'people_count': 2,
        },
        'today': {'credit': 0, 'debit': 0, 'settled': 0, 'count': 0},
        'cash_in_hand': {
          'base_currency': 'INR',
          'position': 649900,
          'receivable': 649900,
          'payable': 0,
          'settled': 5000,
          'today': 1000,
          'today_count': 2,
          'people_count': 2,
        },
        'opening': {
          'base_currency': 'INR',
          'position': 50000,
          'receivable': 50000,
          'payable': 0,
          'settled': 0,
          'today': 0,
          'today_count': 0,
          'people_count': 1,
        },
        'recent_activity': [],
        'people_with_balance': [],
      });

      expect(dash.cashInHand, isNotNull);
      expect(dash.openingTotal, isNotNull);
      expect(dash.cashInHand!.positionMinor, 649900);
      expect(dash.openingTotal!.positionMinor, 50000);

      // The two totals add up to the net position — so neither contains the
      // other, and nothing is counted twice.
      expect(
        dash.cashInHand!.positionMinor + dash.openingTotal!.positionMinor,
        dash.summary.netPosition,
      );
    });

    test('a database older than 0022 reports neither, and the screen falls back',
        () {
      final dash = Dashboard.fromJson(const {
        'profile': {'name': 'Ved', 'currency': 'INR'},
        'base_currency': 'INR',
        'summary': {
          'total_receivable': 1,
          'total_payable': 0,
          'net_position': 1,
          'people_with_balance': 1,
          'people_count': 1,
        },
        'today': {'credit': 0, 'debit': 0, 'settled': 0, 'count': 0},
        'recent_activity': [],
        'people_with_balance': [],
      });

      expect(dash.cashInHand, isNull);
      expect(dash.openingTotal, isNull);
    });
  });

  group('opening-balance actions are not regular transactions', () {
    Map<String, dynamic> entry({
      required String id,
      required String kind,
      required String type,
      required int amount,
      bool openingScope = false,
      String? openingRole,
    }) =>
        {
          'id': id,
          'entry_kind': kind,
          'entry_type': type,
          'money_direction': type == 'credit' ? 'in' : (type == 'debit' ? 'out' : type),
          'amount_minor': amount,
          'entry_date': '2026-08-29',
          'created_at': '2026-08-29T07:10:46.506402+00:00',
          'is_void': false,
          'is_opening': openingRole != null,
          'opening_role': openingRole,
          'opening_scope': openingScope,
          'entry_amount_minor': amount,
          'entry_currency': 'INR',
          'ledger_currency': 'INR',
          'amount_base_minor': amount,
          'base_currency': 'INR',
        };

    test('credits, debits and settlements against the opening balance are in '
        'the opening section and not among the transactions', () {
      final parsed = PersonPage.fromJson(page(
        timeline: [
          entry(id: 'r1', kind: 'transaction', type: 'credit', amount: 50000),
        ],
        openingActivity: [
          entry(
            id: 'o1',
            kind: 'transaction',
            type: 'credit',
            amount: 100000,
            openingScope: true,
            openingRole: 'adjustment',
          ),
          entry(
            id: 'o2',
            kind: 'transaction',
            type: 'debit',
            amount: 50000,
            openingScope: true,
            openingRole: 'adjustment',
          ),
          entry(
            id: 'o3',
            kind: 'settlement',
            type: 'out',
            amount: 50000,
            openingScope: true,
          ),
        ],
      ));

      expect(parsed.timeline, hasLength(1));
      expect(parsed.openingActivity, hasLength(3));

      // Not one opening-book row reaches the regular timeline.
      expect(
        parsed.timeline.where((row) => row.openingScope),
        isEmpty,
      );
      // And every opening-activity row knows it belongs to the opening book.
      expect(parsed.openingActivity.every((row) => row.openingScope), isTrue);
      expect(
        parsed.openingActivity.where((row) => row.isOpeningAdjustment),
        hasLength(2),
      );
    });

    test('an adjustment is labelled as an opening credit or debit, never as a '
        'plain transaction', () {
      final parsed = PersonPage.fromJson(page(
        openingActivity: [
          entry(
            id: 'o1',
            kind: 'transaction',
            type: 'credit',
            amount: 100000,
            openingScope: true,
            openingRole: 'adjustment',
          ),
        ],
      ));

      // `credit` is the stored enum for the OWNER → PERSON direction, which the
      // product calls a Debit — see docs/accounting-direction.md. The statement
      // must go through that mapping like every other screen.
      expect(rowType(parsed.openingActivity.single), 'Opening debit');
    });
  });

  group('settling the opening balance settles the BOOK', () {
    // Found by driving the Windows binary, not by a test: with a ₹5,000 opening
    // balance, a ₹1,000 opening credit and a ₹500 opening debit, the settle
    // sheet offered ₹5,000 — the balance row's own remainder — while the book
    // had ₹4,500 left. `settle_opening_balance()` settles the book and refuses
    // more than its remainder, so the default was a figure that could only
    // fail. The sheet now reads `openingPosition`, which is what this pins.
    test('the outstanding figure is the position, not the balance row', () {
      final parsed = PersonPage.fromJson(page());

      // The balance row still says 4,50,000 is left of ITSELF…
      expect(parsed.opening!.remainingMinor, 450000);
      // …and the book's position is what the server will actually accept.
      expect(parsed.openingPosition.positionMinor.abs(), 450000);
    });

    test('and they part company as soon as an adjustment exists', () {
      // The shape the binary was in: a 5,000 balance row with nothing settled
      // against it, and a book worth 4,500 after the two adjustments.
      final parsed = PersonPage.fromJson({
        ...page(),
        'opening': {
          ...opening(amount: 500000, type: 'credit'),
          'settled_minor': 0,
          'remaining_minor': 500000,
          'status': 'open',
        },
        'opening_position': const {
          'currency': 'INR',
          'base_currency': 'INR',
          'position': 450000,
          'position_base': 450000,
          'receivable': 450000,
          'payable': 0,
          'settled': 0,
          'credit': 550000,
          'debit': 100000,
          'entry_count': 3,
        },
      });

      expect(parsed.opening!.remainingMinor, 500000);
      expect(parsed.openingPosition.positionMinor, 450000);
      // The sheet must offer the second figure. Offering the first is the bug.
      expect(
        parsed.openingPosition.positionMinor,
        isNot(parsed.opening!.remainingMinor),
      );
    });
  });

  group('the statement says the same thing the screen does', () {
    test('the running balance ends on the position it was given', () {
      final parsed = PersonPage.fromJson(page(
        timeline: [
          {
            'id': 'r1',
            'entry_kind': 'transaction',
            'entry_type': 'credit',
            'money_direction': 'in',
            'amount_minor': 100000,
            'entry_date': '2026-08-27',
            'created_at': '2026-08-27T10:00:00.000000+00:00',
            'is_void': false,
            'entry_amount_minor': 100000,
            'entry_currency': 'INR',
            'ledger_currency': 'INR',
            'base_currency': 'INR',
          },
          {
            'id': 'r2',
            'entry_kind': 'transaction',
            'entry_type': 'credit',
            'money_direction': 'in',
            'amount_minor': 500000,
            'entry_date': '2026-08-28',
            'created_at': '2026-08-28T10:00:00.000000+00:00',
            'is_void': false,
            'entry_amount_minor': 500000,
            'entry_currency': 'INR',
            'ledger_currency': 'INR',
            'base_currency': 'INR',
          },
        ],
      ));

      final rows = buildStatementRows(
        parsed.timeline,
        closingMinor: parsed.regular.positionMinor,
        currency: 'INR',
        baseCurrency: 'INR',
      );

      expect(rows, hasLength(2));
      // Oldest first.
      expect(rows.first.date, '27 Aug 2026');
      // And the last row lands exactly on cash in hand, not near it.
      expect(rows.last.balance, contains('6,000'));
      expect(rows.last.balanceReceivable, isTrue);
    });

    test('a voided row moves nothing', () {
      final voided = TimelineEntry.fromJson(const {
        'id': 'v1',
        'entry_kind': 'transaction',
        'entry_type': 'credit',
        'money_direction': 'in',
        'amount_minor': 999999,
        'entry_date': '2026-08-29',
        'created_at': '2026-08-29T10:00:00.000000+00:00',
        'is_void': true,
      });

      expect(netDelta(voided), 0);
    });
  });
}

