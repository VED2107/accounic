/// The shared backend contract, Dart side (context.md §21, Deliverables #12).
///
/// One-for-one with `web/src/lib/types.ts` and the SQL in db/migrations. When a
/// shape changes in one place it changes in all three.
///
/// Every `*Minor` field is an integer count of minor units. `_int` coerces
/// defensively: PostgREST sends bigint as a JSON number, but a numeric that
/// slipped through as a string would otherwise become a silent `0`.
library;
import '../core/direction.dart';

int _int(Object? value) => switch (value) {
      int v => v,
      num v => v.round(),
      String v => int.tryParse(v) ?? num.tryParse(v)?.round() ?? 0,
      _ => 0,
    };

String? _str(Object? value) {
  final text = value?.toString();
  return (text == null || text.isEmpty) ? null : text;
}

enum PartyType {
  person,
  business;

  static PartyType parse(Object? value) =>
      value == 'business' ? PartyType.business : PartyType.person;

  String get wire => name;
  String get label => this == PartyType.business ? 'Business' : 'Person';
}

/// The stored transaction type. The enum's names are the wire values, which
/// read backwards relative to what the user calls them — see
/// `core/direction.dart` for why, and ask [flow] rather than comparing to a
/// case anywhere outside this file.
enum TxnType {
  credit,
  debit;

  static TxnType parse(Object? value) =>
      value == 'debit' ? TxnType.debit : TxnType.credit;

  String get wire => name;

  /// What this row actually means: who handed money to whom.
  MoneyFlow get flow => this == TxnType.credit ? MoneyFlow.ownerToPerson : MoneyFlow.personToOwner;

  /// Plain language, not accounting language (context.md §8).
  String get label => flow.label;
  String get meaning => flow.meaning;
  String get effect => flow.effect;
  bool get isReceivable => flow.isReceivable;

  /// The stored value for a direction the user picked.
  static TxnType forFlow(MoneyFlow flow) =>
      flow == MoneyFlow.ownerToPerson ? TxnType.credit : TxnType.debit;
}

enum SettlementDirection {
  moneyIn,
  moneyOut;

  static SettlementDirection parse(Object? value) =>
      value == 'out' ? SettlementDirection.moneyOut : SettlementDirection.moneyIn;

  String get wire => this == SettlementDirection.moneyIn ? 'in' : 'out';
}

enum SettlementStatus {
  open,
  partial,
  settled;

  static SettlementStatus? parse(Object? value) => switch (value) {
        'settled' => SettlementStatus.settled,
        'partial' => SettlementStatus.partial,
        'open' => SettlementStatus.open,
        _ => null,
      };
}

/* -------------------------------------------------------------------------- */

class Me {
  const Me({
    required this.id,
    required this.name,
    required this.email,
    required this.currency,
    required this.isActive,
    required this.isAdmin,
    required this.createdAt,
    this.phone,
    this.businessName,
    this.avatarUrl,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? businessName;
  final String? avatarUrl;
  final String currency;
  final bool isActive;
  final bool isAdmin;
  final String createdAt;

  factory Me.fromJson(Map<String, dynamic> json) => Me(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        phone: _str(json['phone']),
        businessName: _str(json['business_name']),
        avatarUrl: _str(json['avatar_url']),
        currency: (json['currency'] as String?) ?? 'INR',
        isActive: json['is_active'] as bool? ?? true,
        isAdmin: json['is_admin'] as bool? ?? false,
        createdAt: (json['created_at'] as String?) ?? '',
      );

  String get firstName => name.split(' ').first;
}

class Person {
  const Person({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.type,
    required this.isArchived,
    this.phone,
    this.email,
    this.address,
    this.notes,
  });

  final String id;
  final String ownerId;
  final String name;
  final PartyType type;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;
  final bool isArchived;

  factory Person.fromJson(Map<String, dynamic> json) => Person(
        id: json['id'] as String,
        ownerId: (json['owner_id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        type: PartyType.parse(json['type']),
        phone: _str(json['phone']),
        email: _str(json['email']),
        address: _str(json['address']),
        notes: _str(json['notes']),
        isArchived: json['is_archived'] as bool? ?? false,
      );
}

/// public.person_balances — the authoritative per-person position.
class PersonBalance {
  const PersonBalance({
    required this.personId,
    required this.name,
    required this.type,
    required this.isArchived,
    required this.totalCredit,
    required this.totalDebit,
    required this.settledIn,
    required this.settledOut,
    required this.totalSettled,
    required this.outstandingReceivable,
    required this.outstandingPayable,
    required this.netBalance,
    required this.transactionCount,
    this.phone,
    this.lastActivityAt,
  });

  final String personId;
  final String name;
  final PartyType type;
  final String? phone;
  final bool isArchived;
  final int totalCredit;
  final int totalDebit;
  final int settledIn;
  final int settledOut;
  final int totalSettled;
  final int outstandingReceivable;
  final int outstandingPayable;
  final int netBalance;
  final int transactionCount;
  final String? lastActivityAt;

  factory PersonBalance.fromJson(Map<String, dynamic> json) => PersonBalance(
        personId: (json['person_id'] ?? json['id']) as String,
        name: (json['name'] as String?) ?? '',
        type: PartyType.parse(json['type']),
        phone: _str(json['phone']),
        isArchived: json['is_archived'] as bool? ?? false,
        totalCredit: _int(json['total_credit']),
        totalDebit: _int(json['total_debit']),
        settledIn: _int(json['settled_in']),
        settledOut: _int(json['settled_out']),
        totalSettled: _int(json['total_settled']),
        outstandingReceivable: _int(json['outstanding_receivable']),
        outstandingPayable: _int(json['outstanding_payable']),
        netBalance: _int(json['net_balance']),
        transactionCount: _int(json['transaction_count']),
        lastActivityAt: _str(json['last_activity_at']),
      );

  bool get hasOutstanding => outstandingReceivable > 0 || outstandingPayable > 0;
}

class OwnerSummary {
  const OwnerSummary({
    required this.totalReceivable,
    required this.totalPayable,
    required this.netPosition,
    required this.peopleWithBalance,
    required this.peopleCount,
  });

  final int totalReceivable;
  final int totalPayable;
  final int netPosition;
  final int peopleWithBalance;
  final int peopleCount;

  factory OwnerSummary.fromJson(Map<String, dynamic> json) => OwnerSummary(
        totalReceivable: _int(json['total_receivable']),
        totalPayable: _int(json['total_payable']),
        netPosition: _int(json['net_position']),
        peopleWithBalance: _int(json['people_with_balance']),
        peopleCount: _int(json['people_count']),
      );
}

class TimelineEntry {
  const TimelineEntry({
    required this.id,
    required this.isSettlement,
    required this.direction,
    required this.amountMinor,
    required this.entryDate,
    required this.isVoid,
    this.note,
    this.settledMinor,
    this.remainingMinor,
    this.status,
    this.txnType,
  });

  final String id;
  final bool isSettlement;
  final SettlementDirection direction;
  final int amountMinor;
  final String entryDate;
  final String? note;
  final bool isVoid;
  final int? settledMinor;
  final int? remainingMinor;
  final SettlementStatus? status;
  final TxnType? txnType;

  factory TimelineEntry.fromJson(Map<String, dynamic> json) {
    final kind = json['entry_kind'] as String?;
    final isSettlement = kind == 'settlement';
    return TimelineEntry(
      id: json['id'] as String,
      isSettlement: isSettlement,
      direction: SettlementDirection.parse(json['money_direction']),
      txnType: isSettlement ? null : TxnType.parse(json['entry_type']),
      amountMinor: _int(json['amount_minor']),
      entryDate: (json['entry_date'] as String?) ?? '',
      note: _str(json['note']),
      isVoid: json['is_void'] as bool? ?? false,
      settledMinor: json['settled_minor'] == null ? null : _int(json['settled_minor']),
      remainingMinor: json['remaining_minor'] == null ? null : _int(json['remaining_minor']),
      status: SettlementStatus.parse(json['status']),
    );
  }

  /// Which way the cash moved. Only meaningful on a settlement.
  bool get isIncoming => direction == SettlementDirection.moneyIn;

  /// Which way the debt runs — what the row is coloured by.
  bool get isReceivable => isSettlement ? isIncoming : (txnType?.isReceivable ?? true);

  String get label => isSettlement
      ? (isIncoming ? 'Settlement received' : 'Settlement paid')
      : (txnType?.label ?? '');
}

class OpenTransaction {
  const OpenTransaction({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.transactionDate,
    required this.remainingMinor,
    required this.settledMinor,
    this.description,
  });

  final String id;
  final TxnType type;
  final int amountMinor;
  final String transactionDate;
  final String? description;
  final int remainingMinor;
  final int settledMinor;

  factory OpenTransaction.fromJson(Map<String, dynamic> json) => OpenTransaction(
        id: json['id'] as String,
        type: TxnType.parse(json['type']),
        amountMinor: _int(json['amount_minor']),
        transactionDate: (json['transaction_date'] as String?) ?? '',
        description: _str(json['description']),
        remainingMinor: _int(json['remaining_minor']),
        settledMinor: _int(json['settled_minor']),
      );
}

/// public.person_page()
class PersonPage {
  const PersonPage({
    required this.person,
    required this.balance,
    required this.timeline,
    required this.timelineTotal,
    required this.openTransactions,
  });

  final Person person;
  final PersonBalance balance;
  final List<TimelineEntry> timeline;
  final int timelineTotal;
  final List<OpenTransaction> openTransactions;

  factory PersonPage.fromJson(Map<String, dynamic> json) => PersonPage(
        person: Person.fromJson(json['person'] as Map<String, dynamic>),
        balance: PersonBalance.fromJson(json['balance'] as Map<String, dynamic>),
        timeline: [
          for (final entry in (json['timeline'] as List? ?? []))
            TimelineEntry.fromJson(entry as Map<String, dynamic>),
        ],
        timelineTotal: _int(json['timeline_total']),
        openTransactions: [
          for (final entry in (json['open_transactions'] as List? ?? []))
            OpenTransaction.fromJson(entry as Map<String, dynamic>),
        ],
      );
}

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.personId,
    required this.personName,
    required this.isSettlement,
    required this.isReceivable,
    required this.amountMinor,
    required this.entryDate,
    this.note,
    this.settlementIncoming = false,
  });

  final String id;
  final String personId;
  final String personName;
  final bool settlementIncoming;
  final bool isSettlement;

  /// True when this entry belongs to the receivable side — money the owner is
  /// owed, or a settlement that retired some of it.
  final bool isReceivable;
  final int amountMinor;
  final String entryDate;
  final String? note;

  factory ActivityItem.fromJson(Map<String, dynamic> json) {
    final type = json['entry_type'] as String?;
    return ActivityItem(
      id: json['id'] as String,
      personId: json['person_id'] as String,
      personName: (json['person_name'] as String?) ?? '',
      isSettlement: json['entry_kind'] == 'settlement',
      isReceivable: entryIsReceivable(type),
      amountMinor: _int(json['amount_minor']),
      entryDate: (json['entry_date'] as String?) ?? '',
      note: _str(json['note']),
      settlementIncoming: type == 'in',
    );
  }

  String get label => isSettlement
      ? (settlementIncoming ? 'Settlement received' : 'Settlement paid')
      : (isReceivable ? MoneyFlow.ownerToPerson.label : MoneyFlow.personToOwner.label);
}

class TodayTotals {
  const TodayTotals({
    required this.credit,
    required this.debit,
    required this.settled,
    required this.count,
  });

  final int credit;
  final int debit;
  final int settled;
  final int count;

  factory TodayTotals.fromJson(Map<String, dynamic> json) => TodayTotals(
        credit: _int(json['credit']),
        debit: _int(json['debit']),
        settled: _int(json['settled']),
        count: _int(json['count']),
      );
}

/// public.dashboard()
class Dashboard {
  const Dashboard({
    required this.summary,
    required this.today,
    required this.recentActivity,
    required this.peopleWithBalance,
    required this.currency,
    required this.name,
  });

  final OwnerSummary summary;
  final TodayTotals today;
  final List<ActivityItem> recentActivity;
  final List<PersonBalance> peopleWithBalance;
  final String currency;
  final String name;

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    final profile = (json['profile'] as Map<String, dynamic>?) ?? const {};
    return Dashboard(
      summary: OwnerSummary.fromJson(json['summary'] as Map<String, dynamic>),
      today: TodayTotals.fromJson(json['today'] as Map<String, dynamic>),
      currency: (profile['currency'] as String?) ?? 'INR',
      name: (profile['name'] as String?) ?? '',
      recentActivity: [
        for (final entry in (json['recent_activity'] as List? ?? []))
          ActivityItem.fromJson(entry as Map<String, dynamic>),
      ],
      peopleWithBalance: [
        for (final entry in (json['people_with_balance'] as List? ?? []))
          PersonBalance.fromJson(entry as Map<String, dynamic>),
      ],
    );
  }
}

class SearchResults {
  const SearchResults({required this.people, required this.transactions});

  final List<PersonBalance> people;
  final List<ActivityItem> transactions;

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
        people: [
          for (final entry in (json['people'] as List? ?? []))
            PersonBalance.fromJson(entry as Map<String, dynamic>),
        ],
        transactions: [
          for (final entry in (json['transactions'] as List? ?? []))
            ActivityItem.fromJson({
              ...entry as Map<String, dynamic>,
              'entry_kind': 'transaction',
              'entry_date': entry['transaction_date'],
              'note': entry['description'],
            }),
        ],
      );

  bool get isEmpty => people.isEmpty && transactions.isEmpty;
}

class ActivityPage {
  const ActivityPage({
    required this.items,
    required this.total,
    required this.hasMore,
  });

  final List<ActivityItem> items;
  final int total;
  final bool hasMore;

  factory ActivityPage.fromJson(Map<String, dynamic> json) => ActivityPage(
        items: [
          for (final entry in (json['items'] as List? ?? []))
            ActivityItem.fromJson(entry as Map<String, dynamic>),
        ],
        total: _int(json['total']),
        hasMore: json['has_more'] as bool? ?? false,
      );
}

/// What every mutation returns: the row, plus the refreshed balance so the UI
/// can reconcile without a second round trip (context.md §14, §23).
class LedgerMutation {
  const LedgerMutation({required this.balance, this.recordId});

  final PersonBalance? balance;
  final String? recordId;

  factory LedgerMutation.fromJson(Map<String, dynamic> json) {
    final record = (json['transaction'] ?? json['settlement']) as Map<String, dynamic>?;
    final balance = json['balance'] as Map<String, dynamic>?;
    return LedgerMutation(
      balance: balance == null ? null : PersonBalance.fromJson(balance),
      recordId: record?['id'] as String?,
    );
  }
}

/// public.activity_summary() — one row per bucket, newest first.
///
/// The only aggregate the product exposes. `credit` and `debit` here are the
/// engine's directions, which are the reverse of the words the user sees; see
/// docs/accounting-direction.md before labelling either of them.
class ActivityBucket {
  const ActivityBucket({
    required this.bucket,
    required this.credit,
    required this.debit,
    required this.settled,
    required this.entries,
  });

  final String bucket;
  final int credit;
  final int debit;
  final int settled;
  final int entries;

  factory ActivityBucket.fromJson(Map<String, dynamic> json) => ActivityBucket(
        bucket: (json['bucket'] as String?) ?? '',
        credit: _int(json['credit']),
        debit: _int(json['debit']),
        settled: _int(json['settled']),
        entries: _int(json['entries']),
      );
}

/// public.admin_list_users() — one row per user in the workspace directory.
///
/// Everything here comes from the SECURITY DEFINER admin RPC, which checks
/// `is_admin()` itself; the client never sees a row it was not entitled to.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.currency,
    required this.isActive,
    required this.isAdmin,
    required this.createdAt,
    required this.peopleCount,
    required this.transactionCount,
    this.phone,
    this.businessName,
    this.lastSignInAt,
  });

  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? businessName;
  final String currency;
  final bool isActive;
  final bool isAdmin;
  final String createdAt;
  final String? lastSignInAt;
  final int peopleCount;
  final int transactionCount;

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? '',
        email: (json['email'] as String?) ?? '',
        phone: _str(json['phone']),
        businessName: _str(json['business_name']),
        currency: (json['currency'] as String?) ?? 'INR',
        isActive: json['is_active'] as bool? ?? true,
        isAdmin: json['is_admin'] as bool? ?? false,
        createdAt: (json['created_at'] as String?) ?? '',
        lastSignInAt: _str(json['last_sign_in_at']),
        peopleCount: _int(json['people_count']),
        transactionCount: _int(json['transaction_count']),
      );
}

class AdminUserPage {
  const AdminUserPage({required this.users, required this.total});

  final List<AdminUser> users;
  final int total;

  factory AdminUserPage.fromJson(Map<String, dynamic> json) => AdminUserPage(
        total: _int(json['total']),
        users: [
          for (final row in (json['users'] as List? ?? []))
            AdminUser.fromJson(Map<String, dynamic>.from(row as Map)),
        ],
      );
}

/// public.admin_system_info()
class SystemInfo {
  const SystemInfo({
    required this.usersTotal,
    required this.usersActive,
    required this.admins,
    required this.peopleTotal,
    required this.transactionsTotal,
    required this.settlementsTotal,
    required this.databaseSize,
    required this.serverTime,
  });

  final int usersTotal;
  final int usersActive;
  final int admins;
  final int peopleTotal;
  final int transactionsTotal;
  final int settlementsTotal;
  final String databaseSize;
  final String serverTime;

  factory SystemInfo.fromJson(Map<String, dynamic> json) => SystemInfo(
        usersTotal: _int(json['users_total']),
        usersActive: _int(json['users_active']),
        admins: _int(json['admins']),
        peopleTotal: _int(json['people_total']),
        transactionsTotal: _int(json['transactions_total']),
        settlementsTotal: _int(json['settlements_total']),
        databaseSize: (json['database_size'] as String?) ?? '',
        serverTime: (json['server_time'] as String?) ?? '',
      );
}
