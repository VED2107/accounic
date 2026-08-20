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
    } catch (error) {
      throw Failure.from(error, 'Your profile could not be loaded.');
    }
  }

  Future<Dashboard> dashboard() async {
    try {
      final data = await _client.rpc(
        'dashboard',
        params: {'p_activity_limit': 12, 'p_people_limit': 8},
      );
      return Dashboard.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      throw Failure.from(error, 'Your dashboard could not be loaded.');
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
    } catch (error) {
      throw Failure.from(error, 'Your people could not be loaded.');
    }
  }

  Future<PersonPage> personPage(String personId, {int limit = 30, int offset = 0}) async {
    try {
      final data = await _client.rpc(
        'person_page',
        params: {'p_person_id': personId, 'p_limit': limit, 'p_offset': offset},
      );
      return PersonPage.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      throw Failure.from(error, 'That account could not be loaded.');
    }
  }

  Future<SearchResults> search(String query) async {
    try {
      final data = await _client.rpc(
        'search_all',
        params: {'p_query': query, 'p_limit': 8},
      );
      return SearchResults.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      throw Failure.from(error, 'Search is unavailable right now.');
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
    } catch (error) {
      throw Failure.from(error, 'Your activity could not be loaded.');
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Writes                                                                  */
  /* ---------------------------------------------------------------------- */

  Future<Person> createPerson({
    required String name,
    PartyType type = PartyType.person,
    String? phone,
    String? email,
    String? address,
    String? notes,
  }) async {
    try {
      final data = await _client.rpc('create_person', params: {
        'p_name': name,
        'p_type': type.wire,
        'p_phone': phone,
        'p_email': email,
        'p_address': address,
        'p_notes': notes,
      });
      return Person.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      throw Failure.from(error, Unchanged.person);
    }
  }

  Future<Person> updatePerson({
    required String personId,
    required String name,
    required PartyType type,
    String? phone,
    String? email,
    String? address,
    String? notes,
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
      });
      return Person.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      throw Failure.from(error, Unchanged.person);
    }
  }

  Future<void> setPersonArchived(String personId, bool archived) async {
    try {
      await _client.rpc('set_person_archived',
          params: {'p_person_id': personId, 'p_archived': archived});
    } catch (error) {
      throw Failure.from(
        error,
        archived ? 'This person could not be archived.' : 'This person could not be restored.',
      );
    }
  }

  Future<void> deletePerson(String personId) async {
    try {
      await _client.rpc('delete_person', params: {'p_person_id': personId});
    } catch (error) {
      throw Failure.from(error, 'This person could not be deleted.');
    }
  }

  Future<LedgerMutation> createTransaction({
    required String personId,
    required TxnType type,
    required int amountMinor,
    required String date,
    String? description,
  }) async {
    try {
      final data = await _client.rpc('create_transaction', params: {
        'p_person_id': personId,
        'p_type': type.wire,
        'p_amount_minor': amountMinor,
        'p_date': date,
        'p_description': description,
      });
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      throw Failure.from(error, Unchanged.transaction);
    }
  }

  Future<LedgerMutation> updateTransaction({
    required String transactionId,
    required TxnType type,
    required int amountMinor,
    required String date,
    String? description,
  }) async {
    try {
      final data = await _client.rpc('update_transaction', params: {
        'p_transaction_id': transactionId,
        'p_type': type.wire,
        'p_amount_minor': amountMinor,
        'p_date': date,
        'p_description': description,
      });
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      throw Failure.from(error, Unchanged.transaction);
    }
  }

  Future<LedgerMutation> voidTransaction(String transactionId, {String? reason}) async {
    try {
      final data = await _client.rpc('void_transaction',
          params: {'p_transaction_id': transactionId, 'p_reason': reason});
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      throw Failure.from(
        error,
        'This transaction could not be voided. Your balance has not been changed.',
      );
    }
  }

  /// Records a settlement.
  ///
  /// When [transactionId] is supplied the direction is left null on purpose:
  /// the database derives it from that transaction's type, which removes a
  /// whole class of client mistakes (context.md §9).
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
    } catch (error) {
      throw Failure.from(error, Unchanged.settlement);
    }
  }

  Future<LedgerMutation> voidSettlement(String settlementId, {String? reason}) async {
    try {
      final data = await _client.rpc('void_settlement',
          params: {'p_settlement_id': settlementId, 'p_reason': reason});
      return LedgerMutation.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      throw Failure.from(
        error,
        'This settlement could not be reversed. Your balance has not been changed.',
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
    } catch (error) {
      throw Failure.from(error, Unchanged.profile);
    }
  }
}

enum PeopleSort { name, balance, recent }
