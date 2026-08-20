import 'package:flutter_test/flutter_test.dart';
import 'package:accounic/core/direction.dart';
import 'package:accounic/data/models.dart';

/// Contract tests (context.md §21, §33).
///
/// These guard the seam between the database and the Dart client: the balances
/// the app displays must be exactly what `person_balances` computed, with no
/// re-derivation and no type drift. The payloads below are shaped exactly like
/// the RPC responses in db/migrations/0003 and 0004.
void main() {
  group('PersonBalance', () {
    test('reads the engine s numbers verbatim', () {
      final balance = PersonBalance.fromJson(const {
        'person_id': 'p1',
        'name': 'Rahul Traders',
        'type': 'business',
        'phone': '+91 98200 11223',
        'is_archived': false,
        'total_credit': 2100000,
        'total_debit': 0,
        'settled_in': 400000,
        'settled_out': 0,
        'total_settled': 400000,
        'outstanding_receivable': 1700000,
        'outstanding_payable': 0,
        'net_balance': 1700000,
        'transaction_count': 3,
        'last_activity_at': '2026-08-18',
      });

      expect(balance.outstandingReceivable, 1700000);
      expect(balance.netBalance, 1700000);
      expect(balance.hasOutstanding, isTrue);
      expect(balance.type, PartyType.business);
    });

    test('keeps both sides of a mixed account (context.md §6)', () {
      final balance = PersonBalance.fromJson(const {
        'person_id': 'p2',
        'name': 'Kumar Hardware',
        'type': 'business',
        'is_archived': false,
        'total_credit': 40000,
        'total_debit': 225000,
        'settled_in': 0,
        'settled_out': 0,
        'total_settled': 0,
        'outstanding_receivable': 40000,
        'outstanding_payable': 225000,
        'net_balance': -185000,
        'transaction_count': 2,
      });

      expect(balance.outstandingReceivable, 40000);
      expect(balance.outstandingPayable, 225000);
      expect(balance.netBalance, -185000);
    });

    test('a numeric that arrives as a string still becomes an int, not zero', () {
      // Defensive: PostgREST sends bigint as a JSON number today, but a schema
      // change that reintroduced numeric must not silently zero every balance.
      final balance = PersonBalance.fromJson(const {
        'person_id': 'p3',
        'name': 'Test',
        'type': 'person',
        'is_archived': false,
        'total_credit': '1000000',
        'total_debit': '0',
        'settled_in': '0',
        'settled_out': '0',
        'total_settled': '0',
        'outstanding_receivable': '1000000',
        'outstanding_payable': '0',
        'net_balance': '1000000',
        'transaction_count': '1',
      });

      expect(balance.netBalance, 1000000);
      expect(balance.totalCredit, 1000000);
    });

    test('missing optional fields do not throw', () {
      final balance = PersonBalance.fromJson(const {
        'person_id': 'p4',
        'name': 'Sparse',
        'type': 'person',
        'is_archived': false,
      });

      expect(balance.netBalance, 0);
      expect(balance.phone, isNull);
      expect(balance.hasOutstanding, isFalse);
    });
  });

  group('TimelineEntry', () {
    test('a partially settled credit reports what is left', () {
      final entry = TimelineEntry.fromJson(const {
        'id': 't1',
        'entry_kind': 'transaction',
        'entry_type': 'credit',
        'money_direction': 'in',
        'amount_minor': 1050000,
        'entry_date': '2026-07-29',
        'note': 'Invoice #101',
        'is_void': false,
        'settled_minor': 400000,
        'remaining_minor': 650000,
        'status': 'partial',
      });

      expect(entry.isSettlement, isFalse);
      expect(entry.txnType, TxnType.credit);
      expect(entry.status, SettlementStatus.partial);
      expect(entry.remainingMinor, 650000);

      // The stored 'credit' is the owner-to-person direction, which the product
      // calls a debit and shows in green — see docs/accounting-direction.md.
      expect(entry.isReceivable, isTrue);
      expect(entry.label, 'Debit');
    });

    test('a settlement carries no per-transaction status', () {
      final entry = TimelineEntry.fromJson(const {
        'id': 's1',
        'entry_kind': 'settlement',
        'entry_type': 'out',
        'money_direction': 'out',
        'amount_minor': 600000,
        'entry_date': '2026-08-10',
        'note': 'Cheque 004512',
        'is_void': false,
      });

      expect(entry.isSettlement, isTrue);
      expect(entry.txnType, isNull);
      expect(entry.status, isNull);
      expect(entry.label, 'Settlement paid');
    });

    test('a voided entry is still readable history (context.md §17)', () {
      final entry = TimelineEntry.fromJson(const {
        'id': 't2',
        'entry_kind': 'transaction',
        'entry_type': 'debit',
        'money_direction': 'out',
        'amount_minor': 999900,
        'entry_date': '2026-08-01',
        'is_void': true,
      });

      expect(entry.isVoid, isTrue);
      expect(entry.amountMinor, 999900);
    });
  });

  group('Dashboard', () {
    test('parses the whole payload in one pass', () {
      final dashboard = Dashboard.fromJson(const {
        'profile': {'id': 'u1', 'name': 'Ved Chauhan', 'currency': 'INR'},
        'summary': {
          'total_receivable': 2075000,
          'total_payable': 335000,
          'net_position': 1740000,
          'people_with_balance': 4,
          'people_count': 5,
        },
        'today': {'credit': 75000, 'debit': 0, 'settled': 0, 'count': 1},
        'recent_activity': [
          {
            'id': 'a1',
            'person_id': 'p1',
            'person_name': 'Anil Deshmukh',
            'entry_kind': 'transaction',
            'entry_type': 'credit',
            'amount_minor': 75000,
            'entry_date': '2026-08-19',
            'note': 'Lent cash',
          }
        ],
        'people_with_balance': [
          {
            'person_id': 'p1',
            'name': 'Rahul Traders',
            'type': 'business',
            'is_archived': false,
            'net_balance': 1700000,
            'outstanding_receivable': 1700000,
            'outstanding_payable': 0,
          }
        ],
      });

      expect(dashboard.currency, 'INR');
      expect(dashboard.name, 'Ved Chauhan');
      expect(dashboard.summary.totalReceivable, 2075000);
      expect(dashboard.summary.netPosition, 1740000);
      expect(dashboard.today.credit, 75000);
      expect(dashboard.recentActivity.single.personName, 'Anil Deshmukh');
      expect(dashboard.recentActivity.single.isReceivable, isTrue);
      expect(dashboard.peopleWithBalance.single.netBalance, 1700000);
    });

    test('an empty workspace produces zeros, not nulls', () {
      final dashboard = Dashboard.fromJson(const {
        'profile': {'id': 'u1', 'name': 'New User', 'currency': 'INR'},
        'summary': {
          'total_receivable': 0,
          'total_payable': 0,
          'net_position': 0,
          'people_with_balance': 0,
          'people_count': 0,
        },
        'today': {'credit': 0, 'debit': 0, 'settled': 0, 'count': 0},
        'recent_activity': [],
        'people_with_balance': [],
      });

      expect(dashboard.summary.netPosition, 0);
      expect(dashboard.recentActivity, isEmpty);
    });
  });

  group('LedgerMutation', () {
    test('carries the refreshed balance so the UI need not refetch', () {
      final mutation = LedgerMutation.fromJson(const {
        'transaction': {'id': 't9', 'amount_minor': 1000000},
        'balance': {
          'person_id': 'p1',
          'name': 'Smoke Test Co',
          'type': 'business',
          'is_archived': false,
          'outstanding_receivable': 600000,
          'outstanding_payable': 0,
          'net_balance': 600000,
        },
      });

      expect(mutation.recordId, 't9');
      expect(mutation.balance!.outstandingReceivable, 600000);
    });
  });

  group('direction (docs/accounting-direction.md)', () {
    test('a person handing money to the owner is a payable credit', () {
      // Rahul gives Ved 5,000: Ved holds Rahul's money, so Ved owes it back.
      const flow = Flow.personToOwner;

      expect(flow.label, 'Credit');
      expect(flow.meaning, 'They gave me money');
      expect(flow.effect, 'I owe them');
      expect(flow.isReceivable, isFalse);
      expect(flow.wire, 'debit');
      expect(TxnType.forFlow(flow), TxnType.debit);
    });

    test('the owner handing money to a person is a receivable debit', () {
      // Ved gives Rahul 5,000: Rahul owes it back.
      const flow = Flow.ownerToPerson;

      expect(flow.label, 'Debit');
      expect(flow.meaning, 'I gave them money');
      expect(flow.effect, 'They owe me');
      expect(flow.isReceivable, isTrue);
      expect(flow.wire, 'credit');
      expect(TxnType.forFlow(flow), TxnType.credit);
    });

    test('the stored type and the spoken word are opposites, deliberately', () {
      expect(TxnType.credit.label, 'Debit');
      expect(TxnType.debit.label, 'Credit');
      expect(TxnType.credit.isReceivable, isTrue);
      expect(TxnType.debit.isReceivable, isFalse);
    });

    test('settlement direction follows the side it retires', () {
      // Money arriving can only close something the owner was owed.
      expect(entryIsReceivable('in'), isTrue);
      // Money paid out can only close something the owner owed.
      expect(entryIsReceivable('out'), isFalse);
      expect(entryIsReceivable('credit'), isTrue);
      expect(entryIsReceivable('debit'), isFalse);
    });
  });

  group('enums map to the SQL wire values', () {
    test('round trip', () {
      expect(TxnType.parse('credit'), TxnType.credit);
      expect(TxnType.parse('debit'), TxnType.debit);
      expect(TxnType.credit.wire, 'credit');
      expect(TxnType.debit.wire, 'debit');

      expect(SettlementDirection.parse('in'), SettlementDirection.moneyIn);
      expect(SettlementDirection.parse('out'), SettlementDirection.moneyOut);
      expect(SettlementDirection.moneyIn.wire, 'in');
      expect(SettlementDirection.moneyOut.wire, 'out');

      expect(PartyType.parse('business'), PartyType.business);
      expect(PartyType.person.wire, 'person');
    });
  });
}
