import 'package:flutter_test/flutter_test.dart';

import 'package:accounic/core/transfers.dart';
import 'package:accounic/data/models.dart';

/// Transfers, on the Dart side (upgrade 46).
///
/// A transfer leg is stored as an ordinary debit or credit, and the whole point
/// of `core/transfers.dart` is that it must not be *called* one. These tests
/// pin that, because the failure is silent: the balances would still be right
/// and every row would read as a loan that never happened.
///
/// The label strings are also the web client's, character for character —
/// `web/src/lib/transfers.ts` and `web/src/lib/transfers.test.ts` assert the
/// same six. A user moving between the phone and the browser must not be shown
/// two different words for one transfer.
void main() {
  group('transfer labels', () {
    test('say where the money went, from either side', () {
      expect(transferLabel(TransferRole.source, 'Dhruv'), 'Transfer to Dhruv');
      expect(transferLabel(TransferRole.destination, 'Ved'), 'Transfer from Ved');
    });

    test('still read as a transfer when the other party is unknown', () {
      // An archived or deleted counterparty must not produce "Transfer to null".
      expect(transferLabel(TransferRole.source, null), 'Transfer out');
      expect(transferLabel(TransferRole.destination, null), 'Transfer in');
      expect(transferLabel(TransferRole.source, '   '), 'Transfer out');
      expect(transferLabel(null, 'Dhruv'), 'Transfer');
    });
  });

  group('transfer direction', () {
    test('credits the destination and debits the source', () {
      expect(transferIsIncoming(TransferRole.destination), isTrue);
      expect(transferIsIncoming(TransferRole.source), isFalse);
      expect(transferSign(TransferRole.destination), '+');
      expect(transferSign(TransferRole.source), '−');
    });

    test('parses the wire values and refuses anything else', () {
      expect(TransferRole.parse('source'), TransferRole.source);
      expect(TransferRole.parse('destination'), TransferRole.destination);
      expect(TransferRole.parse(null), isNull);
      expect(TransferRole.parse('sideways'), isNull);
    });
  });

  group('a transfer leg on the timeline', () {
    TimelineEntry leg(String role, String? name) => TimelineEntry.fromJson({
          'id': 't-leg',
          'entry_kind': 'transaction',
          'entry_type': role == 'source' ? 'debit' : 'credit',
          'money_direction': role == 'source' ? 'out' : 'in',
          'amount_minor': 300000,
          'entry_date': '2026-08-24',
          'is_void': false,
          'created_at': '2026-08-24T09:00:00.000Z',
          'transfer_id': 'tr-1',
          'transfer_role': role,
          'transfer_counterparty_name': name,
        });

    test('knows it is one, and names the other party instead of the type', () {
      final source = leg('source', 'Dhruv');
      expect(source.isTransfer, isTrue);
      expect(source.transferRole, TransferRole.source);
      expect(source.label, 'Transfer to Dhruv');

      final destination = leg('destination', 'Ved');
      expect(destination.isTransfer, isTrue);
      expect(destination.label, 'Transfer from Ved');
    });

    test('never falls back to the credit/debit vocabulary', () {
      // The source leg is stored as a debit, which this product's direction
      // rule calls "Credit". For a transfer that is simply the wrong word.
      expect(leg('source', 'Dhruv').label, isNot(contains('Credit')));
      expect(leg('destination', 'Ved').label, isNot(contains('Debit')));
    });

    test('an ordinary entry is not a transfer', () {
      final ordinary = TimelineEntry.fromJson({
        'id': 'e1',
        'entry_kind': 'transaction',
        'entry_type': 'credit',
        'money_direction': 'in',
        'amount_minor': 100000,
        'entry_date': '2026-08-24',
        'is_void': false,
      });
      expect(ordinary.isTransfer, isFalse);
      expect(ordinary.transferRole, isNull);
      expect(ordinary.label, 'Debit');
    });
  });

  group('the transfer record', () {
    test('keeps all three amounts, and the rate that links two of them', () {
      final transfer = Transfer.fromJson({
        'id': 'tr-1',
        'from_person_id': 'p1',
        'to_person_id': 'p2',
        'transfer_date': '2026-08-26',
        'entry_amount_minor': 10000,
        'entry_currency': 'USD',
        'from_amount_minor': 10000,
        'from_currency': 'USD',
        'to_amount_minor': 954276,
        'to_currency': 'INR',
        'exchange_rate_e9': 95427612000,
        'exchange_rate_source': 'test',
        'is_void': false,
      });

      expect(transfer.isConverted, isTrue);
      expect(transfer.entryAmountMinor, 10000);
      expect(transfer.fromAmountMinor, 10000);
      expect(transfer.toAmountMinor, 954276);
      expect(transfer.exchangeRateE9, 95427612000);
    });

    test('a same-currency transfer carries the same figure on both sides', () {
      final transfer = Transfer.fromJson({
        'id': 'tr-2',
        'from_person_id': 'p1',
        'to_person_id': 'p2',
        'transfer_date': '2026-08-24',
        'entry_amount_minor': 300000,
        'entry_currency': 'INR',
        'from_amount_minor': 300000,
        'from_currency': 'INR',
        'to_amount_minor': 300000,
        'to_currency': 'INR',
        'is_void': false,
      });

      expect(transfer.isConverted, isFalse);
      expect(transfer.fromAmountMinor, transfer.toAmountMinor);
      expect(transfer.exchangeRateE9, isNull);
    });
  });
}
