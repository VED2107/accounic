/// The shared backend contract, Dart side (context.md §21, Deliverables #12).
///
/// One-for-one with `web/src/lib/types.ts` and the SQL in db/migrations. When a
/// shape changes in one place it changes in all three.
///
/// Every `*Minor` field is an integer count of minor units. `_int` coerces
/// defensively: PostgREST sends bigint as a JSON number, but a numeric that
/// slipped through as a string would otherwise become a silent `0`.
library;
import '../core/currencies.dart';
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

/// Which way an opening balance runs, in the user's words (upgrade §3).
///
/// Stated as a sentence rather than as a transaction type because "credit" is
/// exactly the word people get backwards — see docs/accounting-direction.md.
enum OpeningDirection {
  none,
  theyOweMe,
  iOweThem;

  String get wire => switch (this) {
        OpeningDirection.none => 'none',
        OpeningDirection.theyOweMe => 'they_owe_me',
        OpeningDirection.iOweThem => 'i_owe_them',
      };

  String get label => switch (this) {
        OpeningDirection.none => 'No opening balance',
        OpeningDirection.theyOweMe => 'They owe me',
        OpeningDirection.iOweThem => 'I owe them',
      };
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
    this.currency,
    this.ledgerCurrency,
  });

  final String id;
  final String ownerId;
  final String name;
  final PartyType type;
  final String? phone;
  final String? email;
  final String? address;
  final String? notes;

  /// The person's DEFAULT ENTRY currency: what a new transaction with them is
  /// entered in. Null means the owner's base currency, which is what every
  /// person created before this feature meant (upgrade §1). Changing it never
  /// rewrites history (db/migrations/0013).
  final String? currency;

  /// The currency this person's stored figures are denominated in, frozen the
  /// first time [currency] moved away from it. Null means the two have never
  /// diverged, so the ledger simply follows [currency].
  final String? ledgerCurrency;
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
        currency: _str(json['currency']),
        ledgerCurrency: _str(json['ledger_currency']),
        isArchived: json['is_archived'] as bool? ?? false,
      );

  /// What a new entry for this person should be typed in.
  String entryCurrency(String baseCurrency) =>
      currency ?? baseCurrency;

  /// What this person's already-recorded figures are denominated in. The same
  /// chain the database uses, to the letter.
  String ledgerCurrencyOr(String baseCurrency) =>
      ledgerCurrency ?? currency ?? baseCurrency;

  /// True when this person's history and their entry default have parted ways.
  bool hasSwitchedCurrency(String baseCurrency) =>
      ledgerCurrencyOr(baseCurrency) != entryCurrency(baseCurrency);
}

/// public.person_balances — the authoritative per-person position.
class PersonBalance {
  const PersonBalance({
    required this.personId,
    required this.name,
    required this.type,
    required this.isArchived,
    required this.currency,
    String? defaultCurrency,
    required this.baseCurrency,
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
    this.netBalanceBase,
    this.netBalanceDefault,
    this.openingMinor = 0,
  }) : _defaultCurrency = defaultCurrency;

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

  /// The same position in the owner's base currency, or null when no rate has
  /// been cached for that pair. Null means "not known" and is never treated as
  /// zero (upgrade §9).
  final int? netBalanceBase;

  /// The same position in this person's own default currency. Display only: it
  /// moves when rates move, and equals [netBalance] whenever the two currencies
  /// agree, which is almost always.
  final int? netBalanceDefault;

  /// The opening balance as a signed figure: positive when they owe the user.
  final int openingMinor;

  /// True when this person's history and their entry default have parted ways.
  bool get hasSwitchedCurrency => defaultCurrency != currency;

  /// The currency every figure above is denominated in: this person's ledger
  /// currency, which is what their history was actually recorded in.
  final String currency;

  final String? _defaultCurrency;

  /// What a new entry for this person should default to. Differs from
  /// [currency] only for a person whose currency was changed after they already
  /// had entries (db/migrations/0013); absent, it is simply [currency], which is
  /// what it means for everyone who has never switched.
  String get defaultCurrency => _defaultCurrency ?? currency;
  final String baseCurrency;
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
        currency: (json['currency'] as String?) ?? kFallbackCurrency,
        defaultCurrency: (json['default_currency'] as String?) ??
            (json['currency'] as String?) ??
            kFallbackCurrency,
        baseCurrency: (json['base_currency'] as String?) ??
            (json['currency'] as String?) ??
            kFallbackCurrency,
        netBalanceBase:
            json['net_balance_base'] == null ? null : _int(json['net_balance_base']),
        netBalanceDefault: json['net_balance_default'] == null
            ? null
            : _int(json['net_balance_default']),
        openingMinor: _int(json['opening_minor']),
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
    this.baseCurrency = kFallbackCurrency,
    this.unconvertedPeople = 0,
    this.currencyCount = 1,
  });

  final int totalReceivable;
  final int totalPayable;
  final int netPosition;
  final int peopleWithBalance;
  final int peopleCount;

  /// Every total above is converted into this currency.
  final String baseCurrency;

  /// Accounts left out of the totals because no rate is known for them. Said
  /// out loud on the dashboard rather than quietly under-reporting.
  final int unconvertedPeople;
  final int currencyCount;

  factory OwnerSummary.fromJson(Map<String, dynamic> json) => OwnerSummary(
        totalReceivable: _int(json['total_receivable']),
        totalPayable: _int(json['total_payable']),
        netPosition: _int(json['net_position']),
        peopleWithBalance: _int(json['people_with_balance']),
        peopleCount: _int(json['people_count']),
        baseCurrency: (json['base_currency'] as String?) ?? kFallbackCurrency,
        unconvertedPeople: _int(json['unconverted_people']),
        currencyCount: _int(json['currency_count']),
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
    this.isOpening = false,
    this.enteredAmountMinor,
    this.enteredCurrency,
    this.exchangeRateE9,
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

  /// A balance carried in from before the account existed (upgrade 3).
  final bool isOpening;

  /// What was actually handed over, when that was not the account's currency.
  /// Frozen at entry: a later rate move never touches it (upgrade 8).
  final int? enteredAmountMinor;
  final String? enteredCurrency;
  final int? exchangeRateE9;

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
      isOpening: json['is_opening'] as bool? ?? false,
      enteredAmountMinor:
          json['entered_amount_minor'] == null ? null : _int(json['entered_amount_minor']),
      enteredCurrency: _str(json['entered_currency']),
      exchangeRateE9:
          json['exchange_rate_e9'] == null ? null : _int(json['exchange_rate_e9']),
    );
  }

  /// Which way the cash moved. Only meaningful on a settlement.
  bool get isIncoming => direction == SettlementDirection.moneyIn;

  /// Which way the debt runs — what the row is coloured by.
  bool get isReceivable => isSettlement ? isIncoming : (txnType?.isReceivable ?? true);

  String get label => isOpening
      ? 'Opening balance'
      : isSettlement
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
    this.isOpening = false,
  });

  final String id;
  final TxnType type;
  final int amountMinor;
  final String transactionDate;
  final String? description;
  final int remainingMinor;
  final int settledMinor;
  final bool isOpening;

  factory OpenTransaction.fromJson(Map<String, dynamic> json) => OpenTransaction(
        id: json['id'] as String,
        type: TxnType.parse(json['type']),
        amountMinor: _int(json['amount_minor']),
        transactionDate: (json['transaction_date'] as String?) ?? '',
        description: _str(json['description']),
        remainingMinor: _int(json['remaining_minor']),
        settledMinor: _int(json['settled_minor']),
        isOpening: json['is_opening'] as bool? ?? false,
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
    required this.currency,
    required this.defaultCurrency,
    required this.baseCurrency,
  });

  final Person person;
  final PersonBalance balance;
  final List<TimelineEntry> timeline;
  final int timelineTotal;
  final List<OpenTransaction> openTransactions;

  /// The account's own currency: what every figure on the screen is in. This is
  /// the person's LEDGER currency — what their history was actually recorded in.
  final String currency;

  /// What a new entry for this person should default to. Differs from [currency]
  /// only for a person whose currency was changed after they already had
  /// entries (db/migrations/0013).
  final String defaultCurrency;

  /// The workspace currency, for the equivalent shown beside the position.
  final String baseCurrency;

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
        currency: (json['currency'] as String?) ?? kFallbackCurrency,
        defaultCurrency: (json['default_currency'] as String?) ??
            (json['currency'] as String?) ??
            kFallbackCurrency,
        baseCurrency: (json['base_currency'] as String?) ??
            (json['currency'] as String?) ??
            kFallbackCurrency,
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
    this.currency = kFallbackCurrency,
    this.isOpening = false,
    this.enteredAmountMinor,
    this.enteredCurrency,
    this.exchangeRateE9,
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

  /// The currency this row is denominated in: the person's, not the owner's.
  /// A workspace-wide feed is exactly where two of them sit side by side.
  final String currency;
  final bool isOpening;
  final int? enteredAmountMinor;
  final String? enteredCurrency;
  final int? exchangeRateE9;

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
      currency: (json['currency'] as String?) ?? kFallbackCurrency,
      isOpening: json['is_opening'] as bool? ?? false,
      enteredAmountMinor:
          json['entered_amount_minor'] == null ? null : _int(json['entered_amount_minor']),
      enteredCurrency: _str(json['entered_currency']),
      exchangeRateE9:
          json['exchange_rate_e9'] == null ? null : _int(json['exchange_rate_e9']),
    );
  }

  String get label => isOpening
      ? 'Opening balance'
      : isSettlement
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
    required this.baseCurrency,
  });

  final OwnerSummary summary;
  final TodayTotals today;
  final List<ActivityItem> recentActivity;
  final List<PersonBalance> peopleWithBalance;
  final String currency;

  /// What the headline totals are converted into. The same as [currency] today,
  /// and named separately because they answer different questions.
  final String baseCurrency;
  final String name;

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    final profile = (json['profile'] as Map<String, dynamic>?) ?? const {};
    return Dashboard(
      summary: OwnerSummary.fromJson(json['summary'] as Map<String, dynamic>),
      today: TodayTotals.fromJson(json['today'] as Map<String, dynamic>),
      currency: (profile['currency'] as String?) ?? kFallbackCurrency,
      baseCurrency: (json['base_currency'] as String?) ??
          (profile['currency'] as String?) ??
          kFallbackCurrency,
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
