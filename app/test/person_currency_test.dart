import 'package:flutter_test/flutter_test.dart';

import 'package:accounic/data/models.dart';

/// Per-person currency resolution (v1.1.1, db/migrations/0013).
///
/// The fallback chain is implemented three times — in SQL, in TypeScript and
/// here — because each client has to be able to label a figure without a round
/// trip. These pin the Dart copy to the same rules as the other two. Reading a
/// person's history in the wrong currency is exactly the bug this release
/// corrects, and it would show up here first.
void main() {
  Person person({String? currency, String? ledgerCurrency}) => Person(
        id: 'p1',
        ownerId: 'o1',
        name: 'Ahmed',
        type: PartyType.person,
        isArchived: false,
        currency: currency,
        ledgerCurrency: ledgerCurrency,
      );

  group('Person currency resolution', () {
    test('each person carries their own currency', () {
      expect(person(currency: 'AED').entryCurrency('INR'), 'AED');
      expect(person(currency: 'INR').entryCurrency('INR'), 'INR');
      expect(person(currency: 'USD').entryCurrency('INR'), 'USD');
      expect(person(currency: 'EUR').entryCurrency('INR'), 'EUR');
    });

    test('a person with no currency falls back to the account currency', () {
      final p = person();
      expect(p.entryCurrency('INR'), 'INR');
      expect(p.ledgerCurrencyOr('INR'), 'INR');
      expect(p.hasSwitchedCurrency('INR'), isFalse);
    });

    test('that fallback follows the account rather than freezing a copy', () {
      final p = person();
      expect(p.entryCurrency('INR'), 'INR');
      expect(p.entryCurrency('GBP'), 'GBP');
      expect(p.ledgerCurrencyOr('GBP'), 'GBP');
    });

    test('a person with their own currency ignores the account currency', () {
      final p = person(currency: 'AED');
      expect(p.entryCurrency('INR'), 'AED');
      expect(p.entryCurrency('GBP'), 'AED');
    });

    test('the ledger stays frozen once a person has switched', () {
      // Ahmed's history is in dirhams; his new entries are in dollars.
      final p = person(currency: 'USD', ledgerCurrency: 'AED');
      expect(p.ledgerCurrencyOr('INR'), 'AED');
      expect(p.entryCurrency('INR'), 'USD');
      expect(p.hasSwitchedCurrency('INR'), isTrue);
    });

    test('a person who has never switched has exactly one currency', () {
      final p = person(currency: 'AED');
      expect(p.ledgerCurrencyOr('INR'), p.entryCurrency('INR'));
      expect(p.hasSwitchedCurrency('INR'), isFalse);
    });

    test('reads ledger_currency off the wire', () {
      final p = Person.fromJson({
        'id': 'p1',
        'owner_id': 'o1',
        'name': 'Ahmed',
        'type': 'person',
        'currency': 'USD',
        'ledger_currency': 'AED',
        'is_archived': false,
      });
      expect(p.currency, 'USD');
      expect(p.ledgerCurrency, 'AED');
      expect(p.hasSwitchedCurrency('INR'), isTrue);
    });

    test('an absent ledger_currency is not an error', () {
      final p = Person.fromJson({
        'id': 'p1',
        'owner_id': 'o1',
        'name': 'Rahul',
        'type': 'person',
        'currency': 'INR',
        'is_archived': false,
      });
      expect(p.ledgerCurrency, isNull);
      expect(p.ledgerCurrencyOr('INR'), 'INR');
    });
  });

  group('PersonBalance currency', () {
    PersonBalance balanceFrom(Map<String, dynamic> extra) =>
        PersonBalance.fromJson(<String, dynamic>{
          'person_id': 'p1',
          'name': 'Ahmed',
          'type': 'person',
          'is_archived': false,
          'total_credit': 50000,
          'total_debit': 0,
          'settled_in': 0,
          'settled_out': 0,
          'total_settled': 0,
          'outstanding_receivable': 50000,
          'outstanding_payable': 0,
          'net_balance': 50000,
          'transaction_count': 1,
          'base_currency': 'INR',
          ...extra,
        });

    test('figures are labelled with the ledger currency', () {
      final b = balanceFrom({'currency': 'AED', 'default_currency': 'USD'});
      expect(b.currency, 'AED');
      expect(b.defaultCurrency, 'USD');
      expect(b.hasSwitchedCurrency, isTrue);
    });

    test('a row without default_currency means the two agree', () {
      final b = balanceFrom({'currency': 'AED'});
      expect(b.defaultCurrency, 'AED');
      expect(b.hasSwitchedCurrency, isFalse);
    });

    test('an unconvertible position is null, never zero', () {
      final b = balanceFrom({'currency': 'JPY'});
      expect(b.netBalanceBase, isNull);
      expect(b.netBalanceDefault, isNull);
      expect(b.netBalance, 50000);
    });

    test('carries the display conversions when they are known', () {
      final b = balanceFrom({
        'currency': 'AED',
        'default_currency': 'USD',
        'net_balance_base': 1134000,
        'net_balance_default': 13615,
      });
      expect(b.netBalanceBase, 1134000);
      expect(b.netBalanceDefault, 13615);
      // The authoritative figure is still the ledger one.
      expect(b.netBalance, 50000);
    });
  });
}
