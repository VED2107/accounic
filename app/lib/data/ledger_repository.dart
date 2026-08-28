import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/failure.dart';
import 'models.dart';

/// The single data layer for Android and Windows (context.md §20, §21).
///
/// Every call maps onto the same RPC the web client uses, so the accounting
/// rules are not reimplemented here — or anywhere else. This class holds no
/// arithmetic at all: it fetches numbers the database computed.
///
/// Structured as a repository over an injected client so a local cache or an
/// offline queue can be slotted in later without the UI noticing
/// (context.md §22).
class LedgerRepository {
  LedgerRepository(this._client);

  final SupabaseClient _client;

  /* ---------------------------------------------------------------------- */
  /* Reads                                                                   */
  /* ---------------------------------------------------------------------- */

  Future<Me?> me() async {
    try {
      final data = await _client.rpc('me');
      if (data == null) return null;
      return Me.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, 'Your profile could not be loaded.', stack);
    }
  }

  Future<Dashboard> dashboard() async {
    try {
      final data = await _client.rpc(
        'dashboard',
        params: {'p_activity_limit': 12, 'p_people_limit': 8},
      );
      return Dashboard.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, 'Your dashboard could not be loaded.', stack);
    }
  }

  Future<List<PersonBalance>> people({
    String query = '',
    bool includeArchived = false,
    PeopleSort sort = PeopleSort.name,
  }) async {
    try {
      var request = _client.from('person_balances').select();
      if (!includeArchived) request = request.eq('is_archived', false);

      final trimmed = query.trim().replaceAll(RegExp(r'[%,()]'), '');
      if (trimmed.isNotEmpty) {
        request = request.or('name.ilike.%$trimmed%,phone.ilike.%$trimmed%');
      }

      final rows = await switch (sort) {
        PeopleSort.recent =>
          request.order('last_activity_at', ascending: false, nullsFirst: false).limit(500),
        _ => request.order('name').limit(500),
      };

      final people = [
        for (final row in rows) PersonBalance.fromJson(Map<String, dynamic>.from(row)),
      ];

      // PostgREST cannot order by an expression, and |net| is what the user
      // means by "biggest balance". The list is bounded, so sorting here beats
      // maintaining a view for it.
      if (sort == PeopleSort.balance) {
        people.sort((a, b) => b.netBalance.abs().compareTo(a.netBalance.abs()));
      }
      return people;
    } catch (error, stack) {
      throw Failure.from(error, 'Your people could not be loaded.', stack);
    }
  }

  Future<PersonPage> personPage(String personId, {int limit = 30, int offset = 0}) async {
    try {
      final data = await _client.rpc(
        'person_page',
        params: {'p_person_id': personId, 'p_limit': limit, 'p_offset': offset},
      );
      return PersonPage.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, 'That account could not be loaded.', stack);
    }
  }

  Future<SearchResults> search(String query) async {
    try {
      final data = await _client.rpc(
        'search_all',
        params: {'p_query': query, 'p_limit': 8},
      );
      return SearchResults.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, 'Search is unavailable right now.', stack);
    }
  }

  /// Daily totals for the last [days]. Feeds the activity screen's summary and
  /// nothing else — this is context, not a reporting engine (context.md §30).
  Future<List<ActivityBucket>> activitySummary({
    String bucket = 'day',
    int days = 30,
  }) async {
    try {
      final data = await _client.rpc(
        'activity_summary',
        params: {'p_bucket': bucket, 'p_days': days},
      );
      return [
        for (final row in (data as List? ?? const []))
          ActivityBucket.fromJson(Map<String, dynamic>.from(row as Map)),
      ];
    } catch (error, stack) {
      throw Failure.from(error, 'Your activity totals could not be loaded.', stack);
    }
  }

  Future<ActivityPage> activity({int page = 0, int pageSize = 40, String? kind}) async {
    try {
      final data = await _client.rpc(
        'activity_page',
        params: {
          'p_limit': pageSize,
          'p_offset': page * pageSize,
          'p_kind': kind,
        },
      );
      return ActivityPage.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, 'Your activity could not be loaded.', stack);
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Writes                                                                  */
  /* ---------------------------------------------------------------------- */

  /// Creates a person, optionally in their own currency and optionally with an
  /// opening balance (upgrade §1, §4).
  ///
  /// The opening balance goes through the same conversion path as a
  /// transaction, so "they owe me ₹5,000" on a dirham account records the rupee
  /// figure, the rate, and the dirham amount the database derived from them.
  Future<Person> createPerson({
    required String name,
    PartyType type = PartyType.person,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? currency,
    OpeningDirection opening = OpeningDirection.none,
    int? openingAmountMinor,
    int? openingEnteredMinor,
    String? openingEnteredCurrency,
    int? openingRateE9,
    String? openingRateSource,
    int? openingConvertedMinor,
    String? openingConversionMode,
  }) async {
    try {
      final data = await _client.rpc('create_person', params: {
        'p_name': name,
        'p_type': type.wire,
        'p_phone': phone,
        'p_email': email,
        'p_address': address,
        'p_notes': notes,
        'p_currency': currency,
        'p_opening_direction': opening.wire,
        'p_opening_amount_minor': openingAmountMinor,
        'p_opening_entered_minor': openingEnteredMinor,
        'p_opening_entered_currency': openingEnteredCurrency,
        'p_opening_rate_e9': openingRateE9,
        'p_opening_rate_source': openingRateSource,
        'p_opening_converted_minor': openingConvertedMinor,
        'p_opening_conversion_mode': openingConversionMode,
      });
      return Person.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, Unchanged.person, stack);
    }
  }

  /// Updates a person.
  ///
  /// Changing [currency] on an account that already holds entries affects
  /// FUTURE transactions only: every recorded entry stays exactly as it was
  /// entered, and the account keeps reporting in the currency its history is
  /// written in. It is still refused unless [currencyChangeConfirmed] is set,
  /// because the user is entitled to be told that before it happens — the
  /// database's refusal of the first attempt IS the confirmation step, and
  /// nothing has been written when it is raised (db/migrations/0013).
  Future<Person> updatePerson({
    required String personId,
    required String name,
    required PartyType type,
    String? phone,
    String? email,
    String? address,
    String? notes,
    String? currency,
    bool currencyChangeConfirmed = false,
  }) async {
    try {
      final data = await _client.rpc('update_person', params: {
        'p_person_id': personId,
        'p_name': name,
        'p_type': type.wire,
        'p_phone': phone,
        'p_email': email,
        'p_address': address,
        'p_notes': notes,
        'p_currency': currency,
        'p_currency_change_confirmed': currencyChangeConfirmed,
      });
      return Person.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, Unchanged.person, stack);
    }
  }

  Future<void> setPersonArchived(String personId, bool archived) async {
    try {
      await _client.rpc('set_person_archived',
          params: {'p_person_id': personId, 'p_archived': archived});
    } catch (error, stack) {
      throw Failure.from(
        error,
        archived ? 'This person could not be archived.' : 'This person could not be restored.',
        stack,
      );
    }
  }

  /// Retracts a person's whole history in one call (db/migrations/0014).
  ///
  /// A void, not a delete. Every row keeps its amount, date and rate; the
  /// balance goes to zero and the entries leave the activity feed, while the
  /// person's own timeline keeps showing them marked voided.
  ///
  /// Returns how many rows were retracted, so the caller can say what it did
  /// rather than guess.
  Future<({int transactions, int settlements})> voidPersonHistory(
    String personId, {
    String? reason,
  }) async {
    try {
      final result = await _client.rpc('void_person_history', params: {
        'p_person_id': personId,
        'p_reason': (reason?.trim().isEmpty ?? true) ? null : reason!.trim(),
      });
      final map = (result as Map).cast<String, dynamic>();
      return (
        transactions: (map['transactions_voided'] as num?)?.toInt() ?? 0,
        settlements: (map['settlements_voided'] as num?)?.toInt() ?? 0,
      );
    } catch (error, stack) {
      throw Failure.from(error, 'That history could not be retracted.', stack);
    }
  }

  Future<void> deletePerson(String personId) async {
    try {
      await _client.rpc('delete_person', params: {'p_person_id': personId});
    } catch (error, stack) {
      throw Failure.from(error, 'This person could not be deleted.', stack);
    }
  }

  /// Records a transaction.
  ///
  /// When the user typed in a currency other than the account's, the *entered*
  /// figure and the rate travel and the database derives the account amount
  /// from them — the client never sends a converted number it worked out
  /// itself, which is what keeps the three clients agreeing to the last minor
  /// unit (upgrade §2, §5).
  Future<LedgerMutation> createTransaction({
    required String personId,
    required TxnType type,
    required String date,
    int? amountMinor,
    String? description,
    int? enteredAmountMinor,
    String? enteredCurrency,
    int? exchangeRateE9,
    String? rateSource,
    int? convertedAmountMinor,
    String? conversionMode,
  }) async {
    try {
      final data = await _client.rpc('create_transaction', params: {
        'p_person_id': personId,
        'p_type': type.wire,
        'p_amount_minor': amountMinor,
        'p_date': date,
        'p_description': description,
        'p_entered_amount_minor': enteredAmountMinor,
        'p_entered_currency': enteredCurrency,
        'p_exchange_rate_e9': exchangeRateE9,
        'p_rate_source': rateSource,
        'p_converted_amount_minor': convertedAmountMinor,
        'p_conversion_mode': conversionMode,
      });
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, Unchanged.transaction, stack);
    }
  }

  Future<LedgerMutation> updateTransaction({
    required String transactionId,
    required TxnType type,
    required String date,
    int? amountMinor,
    String? description,
    int? enteredAmountMinor,
    String? enteredCurrency,
    int? exchangeRateE9,
    String? rateSource,
    int? convertedAmountMinor,
    String? conversionMode,
  }) async {
    try {
      final data = await _client.rpc('update_transaction', params: {
        'p_transaction_id': transactionId,
        'p_type': type.wire,
        'p_amount_minor': amountMinor,
        'p_date': date,
        'p_description': description,
        'p_entered_amount_minor': enteredAmountMinor,
        'p_entered_currency': enteredCurrency,
        'p_exchange_rate_e9': exchangeRateE9,
        'p_rate_source': rateSource,
        'p_converted_amount_minor': convertedAmountMinor,
        'p_conversion_mode': conversionMode,
      });
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, Unchanged.transaction, stack);
    }
  }

  Future<LedgerMutation> voidTransaction(String transactionId, {String? reason}) async {
    try {
      final data = await _client.rpc('void_transaction',
          params: {'p_transaction_id': transactionId, 'p_reason': reason});
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(
        error,
        'This transaction could not be voided. Your balance has not been changed.',
        stack,
      );
    }
  }

  /// Records a settlement.
  ///
  /// When [transactionId] is supplied the direction is left null on purpose:
  /// the database derives it from that transaction's type, which removes a
  /// whole class of client mistakes (context.md §9).
  /// Sets, replaces or clears a person's opening balance (upgrade §3).
  ///
  /// Replacing one retracts the previous entry rather than editing it, so the
  /// correction shows in the history instead of quietly rewriting what the
  /// account was opened with. That is the database's behaviour, not this
  /// method's.
  Future<void> setOpeningBalance({
    required String personId,
    required OpeningDirection direction,
    int? amountMinor,
    String? date,
    int? enteredAmountMinor,
    String? enteredCurrency,
    int? exchangeRateE9,
    String? rateSource,
    int? convertedAmountMinor,
    String? conversionMode,
  }) async {
    try {
      await _client.rpc('set_person_opening_balance', params: {
        'p_person_id': personId,
        'p_direction': direction.wire,
        'p_amount_minor': amountMinor,
        'p_date': date,
        'p_entered_amount_minor': enteredAmountMinor,
        'p_entered_currency': enteredCurrency,
        'p_rate_e9': exchangeRateE9,
        'p_rate_source': rateSource,
        'p_converted_amount_minor': convertedAmountMinor,
        'p_conversion_mode': conversionMode,
      });
    } catch (error, stack) {
      throw Failure.from(
        error,
        'That opening balance could not be saved. Your balance has not been changed.',
        stack,
      );
    }
  }

  /// Settles a person's opening balance, and only that (upgrade 48).
  ///
  /// The direction is not sent: `settle_opening_balance()` derives it from the
  /// opening entry, so a client cannot record money coming in against a balance
  /// the user owes. Omitting [amountMinor] settles whatever is left of it,
  /// which is the common case.
  Future<LedgerMutation> settleOpeningBalance({
    required String personId,
    required String date,
    int? amountMinor,
    String? note,
    int? enteredAmountMinor,
    String? enteredCurrency,
    int? exchangeRateE9,
    String? rateSource,
    int? convertedAmountMinor,
    String? conversionMode,
  }) async {
    try {
      final data = await _client.rpc('settle_opening_balance', params: {
        'p_person_id': personId,
        'p_amount_minor': amountMinor,
        'p_date': date,
        'p_note': note,
        'p_entered_amount_minor': enteredAmountMinor,
        'p_entered_currency': enteredCurrency,
        'p_exchange_rate_e9': exchangeRateE9,
        'p_rate_source': rateSource,
        'p_converted_amount_minor': convertedAmountMinor,
        'p_conversion_mode': conversionMode,
      });
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, Unchanged.settlement, stack);
    }
  }

  Future<LedgerMutation> createSettlement({
    required String personId,
    required int amountMinor,
    required String date,
    SettlementDirection? direction,
    String? transactionId,
    String? note,
  }) async {
    try {
      final data = await _client.rpc('create_settlement', params: {
        'p_person_id': personId,
        'p_amount_minor': amountMinor,
        'p_direction': transactionId != null ? null : direction?.wire,
        'p_transaction_id': transactionId,
        'p_date': date,
        'p_note': note,
      });
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, Unchanged.settlement, stack);
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Transfers (upgrade 46)                                                  */
  /*                                                                         */
  /* A transfer is ONE logical record with two linked ledger entries, and     */
  /* every method here operates on the whole of it. There is deliberately no  */
  /* call that touches a single leg: the database refuses that outright, and  */
  /* offering it would be offering a way to lose money from one account       */
  /* without it arriving in the other.                                       */
  /* ---------------------------------------------------------------------- */

  /// Moves money from one person to another.
  ///
  /// The amount is entered in [currency], which defaults to the SOURCE person's
  /// ledger currency, and reaches the destination in two steps — each skipped
  /// when its two currencies are the same, which is the ordinary case:
  ///
  ///     entry --entryRateE9--> source ledger --exchangeRateE9--> destination
  ///
  /// As everywhere else in this client, the entered figure and the rates travel
  /// and the database derives both converted amounts. [convertedAmountMinor] is
  /// the one exception and is an exception on purpose: it is what the user says
  /// actually arrived, so there is nothing to derive it from.
  ///
  /// [clientToken] makes the call idempotent. Send the same token twice — a
  /// double tap, a retried request after a dropped connection — and the
  /// database returns the transfer the first call created instead of moving the
  /// money again.
  Future<TransferResult> createTransfer({
    required String fromPersonId,
    required String toPersonId,
    required int amountMinor,
    required String date,
    String? currency,
    String? note,
    int? entryRateE9,
    int? exchangeRateE9,
    String? rateSource,
    int? convertedAmountMinor,
    String? conversionMode,
    String? clientToken,
  }) async {
    try {
      final data = await _client.rpc('create_transfer', params: {
        'p_from_person_id': fromPersonId,
        'p_to_person_id': toPersonId,
        'p_amount_minor': amountMinor,
        'p_currency': currency,
        'p_date': date,
        'p_note': note,
        'p_entry_rate_e9': entryRateE9,
        'p_exchange_rate_e9': exchangeRateE9,
        'p_rate_source': rateSource,
        'p_converted_amount_minor': convertedAmountMinor,
        'p_conversion_mode': conversionMode,
        'p_client_token': clientToken,
      });
      return TransferResult.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(
        error,
        'That transfer could not be recorded. No balance has been changed.',
        stack,
      );
    }
  }

  /// Retracts a transfer — both sides, in one operation.
  ///
  /// A void, not a delete: both entries stay on both timelines with their
  /// amounts and dates intact, and both balances return to where they were.
  /// The database voids the two legs together and refuses any commit that would
  /// leave one without the other, so this cannot half-succeed.
  Future<TransferResult> voidTransfer(String transferId, {String? reason}) async {
    try {
      final data = await _client.rpc('void_transfer', params: {
        'p_transfer_id': transferId,
        'p_reason': (reason?.trim().isEmpty ?? true) ? null : reason!.trim(),
      });
      return TransferResult.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(
        error,
        'That transfer could not be retracted. No balance has been changed.',
        stack,
      );
    }
  }

  /// Edits the logical transfer, never one side of it.
  ///
  /// The two people are not editable: moving a transfer to a different account
  /// is a different transfer, and the honest way to record that is to retract
  /// this one and make that one.
  Future<TransferResult> updateTransfer({
    required String transferId,
    int? amountMinor,
    String? currency,
    String? date,
    String? note,
    int? entryRateE9,
    int? exchangeRateE9,
    String? rateSource,
    int? convertedAmountMinor,
    String? conversionMode,
  }) async {
    try {
      final data = await _client.rpc('update_transfer', params: {
        'p_transfer_id': transferId,
        'p_amount_minor': amountMinor,
        'p_currency': currency,
        'p_date': date,
        'p_note': note,
        'p_entry_rate_e9': entryRateE9,
        'p_exchange_rate_e9': exchangeRateE9,
        'p_rate_source': rateSource,
        'p_converted_amount_minor': convertedAmountMinor,
        'p_conversion_mode': conversionMode,
      });
      return TransferResult.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(
        error,
        'That transfer could not be changed. No balance has been changed.',
        stack,
      );
    }
  }

  Future<LedgerMutation> voidSettlement(String settlementId, {String? reason}) async {
    try {
      final data = await _client.rpc('void_settlement',
          params: {'p_settlement_id': settlementId, 'p_reason': reason});
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(
        error,
        'This settlement could not be reversed. Your balance has not been changed.',
        stack,
      );
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Administration                                                          */
  /* ---------------------------------------------------------------------- */
  //
  // Only the four SECURITY DEFINER RPCs are reachable from a client binary.
  // Creating a user and resetting a password need the service-role key, which
  // no distributable binary may hold, so those two stay in the web app — see
  // docs/decisions.md §21. Each RPC re-checks is_admin() server-side, so a user
  // who forces the screen open still sees nothing.

  Future<AdminUserPage> adminUsers({String query = '', int limit = 50, int offset = 0}) async {
    try {
      final data = await _client.rpc('admin_list_users', params: {
        'p_query': query.trim().isEmpty ? null : query.trim(),
        'p_limit': limit,
        'p_offset': offset,
      });
      return AdminUserPage.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, 'The user directory could not be loaded.', stack);
    }
  }

  Future<SystemInfo> systemInfo() async {
    try {
      final data = await _client.rpc('admin_system_info');
      return SystemInfo.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error, stack) {
      throw Failure.from(error, 'System information could not be loaded.', stack);
    }
  }

  Future<void> setUserActive(String userId, bool active) async {
    try {
      await _client.rpc('admin_set_user_active',
          params: {'p_user_id': userId, 'p_active': active});
    } catch (error, stack) {
      throw Failure.from(
        error,
        active ? 'That user could not be enabled.' : 'That user could not be disabled.',
        stack,
      );
    }
  }

  Future<void> updateProfile({
    required String name,
    String? phone,
    String? businessName,
    String? currency,
  }) async {
    try {
      await _client.rpc('update_my_profile', params: {
        'p_name': name,
        'p_phone': phone,
        'p_business_name': businessName,
        'p_currency': currency,
        'p_avatar_url': null,
      });
    } catch (error, stack) {
      throw Failure.from(error, Unchanged.profile, stack);
    }
  }
}

enum PeopleSort { name, balance, recent }
