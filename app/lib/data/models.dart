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
import '../core/transfers.dart';
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
    this.cashInHandMinor = 0,
    this.cashInHandBase,
    this.openingNetMinor = 0,
    this.openingNetBase,
    this.regularReceivable = 0,
    this.regularPayable = 0,
    this.regularSettledTotal = 0,
    this.openingReceivable = 0,
    this.openingPayable = 0,
    this.openingSettledTotal = 0,
    this.openingEntryCount = 0,
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
  /// The GROSS figure — what the account was carried in with, before anything
  /// was settled against it. For what is left of it, see [openingNetMinor].
  final int openingMinor;

  /// The two halves of [netBalance] (db/migrations/0022).
  ///
  ///     cashInHandMinor + openingNetMinor == netBalance
  ///
  /// always, and the database asserts it. [cashInHandMinor] is the regular
  /// trading position — credits, debits, transfers and their settlements — and
  /// never contains the opening balance. [openingNetMinor] is what is left of
  /// the opening book: the balance the account opened with, plus any credit or
  /// debit recorded against it, less whatever has been settled against it.
  ///
  /// They are shown as two figures and never added together on screen.
  final int cashInHandMinor;
  final int? cashInHandBase;
  final int openingNetMinor;
  final int? openingNetBase;

  /// The halves of each, for the sides a screen shows under the headline.
  final int regularReceivable;
  final int regularPayable;
  final int regularSettledTotal;
  final int openingReceivable;
  final int openingPayable;
  final int openingSettledTotal;

  /// How many rows the opening book holds. Zero means the account has no
  /// opening balance at all, which is not the same as one of zero.
  final int openingEntryCount;

  /// True when this account has an opening book worth showing its own section
  /// for.
  bool get hasOpening => openingEntryCount > 0 || openingMinor != 0;

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
        // Absent against a database older than 0022. Falling back to the whole
        // position is the honest reading there: without the split, everything
        // the account holds is what it holds.
        cashInHandMinor: json['cash_in_hand_minor'] == null
            ? _int(json['net_balance'])
            : _int(json['cash_in_hand_minor']),
        cashInHandBase: json['cash_in_hand_base'] == null
            ? null
            : _int(json['cash_in_hand_base']),
        openingNetMinor: _int(json['opening_net_minor']),
        openingNetBase:
            json['opening_net_base'] == null ? null : _int(json['opening_net_base']),
        regularReceivable: json['regular_receivable'] == null
            ? _int(json['outstanding_receivable'])
            : _int(json['regular_receivable']),
        regularPayable: json['regular_payable'] == null
            ? _int(json['outstanding_payable'])
            : _int(json['regular_payable']),
        regularSettledTotal: json['regular_settled_total'] == null
            ? _int(json['total_settled'])
            : _int(json['regular_settled_total']),
        openingReceivable: _int(json['opening_receivable']),
        openingPayable: _int(json['opening_payable']),
        openingSettledTotal: _int(json['opening_settled_total']),
        openingEntryCount: _int(json['opening_entry_count']),
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
    this.openingRole,
    this.openingScope = false,
    this.enteredAmountMinor,
    this.enteredCurrency,
    this.exchangeRateE9,
    this.exchangeRateSource,
    this.conversionMode,
    this.autoConvertedAmountMinor,
    int? entryAmountMinor,
    String? entryCurrency,
    this.amountBaseMinor,
    this.baseCurrency,
    this.transferId,
    this.transferRole,
    this.transferCounterpartyId,
    this.transferCounterpartyName,
    this.createdAt = '',
  })  : _entryAmountMinor = entryAmountMinor,
        _entryCurrency = entryCurrency;

  final String id;
  final bool isSettlement;

  /// When the row was written, as opposed to the day it is dated. A statement
  /// prints both, because two entries on one day are otherwise
  /// indistinguishable on paper — and it is what orders rows within a day.
  final String createdAt;
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

  /// Which part of the opening book this row is: 'balance' for what the account
  /// opened with, 'adjustment' for a credit or debit recorded against it. Null
  /// on a settlement and on every ordinary transaction (db/migrations/0022).
  final String? openingRole;

  /// True when the row belongs to the opening book at all — including a
  /// settlement made against the opening balance, which is not itself flagged.
  /// The regular timeline holds no row for which this is true.
  final bool openingScope;

  /// True when this row is a credit or debit recorded against the opening
  /// balance rather than what the account opened with.
  bool get isOpeningAdjustment => openingRole == 'adjustment';

  /// What was actually handed over, when that was not the account's currency.
  /// Frozen at entry: a later rate move never touches it (upgrade 8).
  final int? enteredAmountMinor;
  final String? enteredCurrency;
  final int? exchangeRateE9;

  /// Where that rate came from: 'live', a cache label, or the marker a
  /// hand-typed rate is stored under (db/migrations/0018).
  final String? exchangeRateSource;

  /// What was actually entered, and what this row is worth in the workspace
  /// currency (db/migrations/0018). [amountMinor] stays the LEDGER figure — the
  /// one every balance is summed from — so these exist to let a row show the
  /// original amount as its headline without any client converting anything.
  final int? _entryAmountMinor;
  final String? _entryCurrency;
  final int? amountBaseMinor;
  final String? baseCurrency;

  int entryAmountMinorOr(String ledgerCurrency) => _entryAmountMinor ?? amountMinor;
  String entryCurrencyOr(String ledgerCurrency) => _entryCurrency ?? ledgerCurrency;

  /// True when a human typed the rate this row was written at (upgrade 45).
  bool get isManualRate => rateIsManual(exchangeRateSource);

  /// 'automatic' | 'manual' | null. Null means the row was never converted;
  /// a pre-v1.1.2 converted row reads as 'automatic', because the feed resolves
  /// that rather than passing its stored NULL through (upgrade 40).
  final String? conversionMode;

  /// What the recorded rate said the entry was worth. Present only on a manual
  /// row, where [amountMinor] is instead what actually changed hands.
  final int? autoConvertedAmountMinor;

  /// True when somebody said the rate got it wrong and gave the real figure.
  bool get isManualConversion => conversionMode == 'manual';

  /// The transfer this row is one half of (db/migrations/0020).
  ///
  /// Null on an ordinary entry, which is every entry written before transfers
  /// existed. [transferRole] says which side this row is, and the counterparty
  /// is the OTHER person — the one the money went to or came from.
  final String? transferId;
  final TransferRole? transferRole;
  final String? transferCounterpartyId;
  final String? transferCounterpartyName;

  /// True when this row is one leg of a transfer rather than an entry of its
  /// own. Such a row is never settled and never edited on its own: both are
  /// refused by the database, and the screen agrees with it.
  bool get isTransfer => transferId != null;

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
      createdAt: (json['created_at'] as String?) ?? '',
      isOpening: json['is_opening'] as bool? ?? false,
      openingRole: _str(json['opening_role']),
      // Absent against a database older than 0022, where the only rows that
      // belonged to the opening book were the flagged transactions themselves.
      openingScope:
          json['opening_scope'] as bool? ?? (json['is_opening'] as bool? ?? false),
      enteredAmountMinor:
          json['entered_amount_minor'] == null ? null : _int(json['entered_amount_minor']),
      enteredCurrency: _str(json['entered_currency']),
      exchangeRateE9:
          json['exchange_rate_e9'] == null ? null : _int(json['exchange_rate_e9']),
      exchangeRateSource: _str(json['exchange_rate_source']),
      conversionMode: _str(json['conversion_mode']),
      autoConvertedAmountMinor: json['auto_converted_amount_minor'] == null
          ? null
          : _int(json['auto_converted_amount_minor']),
      // Present from 0018 on; absent against an older database, where the
      // getters fall back to the ledger figure exactly as this screen did
      // before.
      entryAmountMinor:
          json['entry_amount_minor'] == null ? null : _int(json['entry_amount_minor']),
      entryCurrency: _str(json['entry_currency']),
      amountBaseMinor:
          json['amount_base_minor'] == null ? null : _int(json['amount_base_minor']),
      baseCurrency: _str(json['base_currency']),
      // Present from 0020 on; absent against an older database, where every
      // row is simply not part of a transfer — which is true.
      transferId: _str(json['transfer_id']),
      transferRole: TransferRole.parse(json['transfer_role']),
      transferCounterpartyId: _str(json['transfer_counterparty_id']),
      transferCounterpartyName: _str(json['transfer_counterparty_name']),
    );
  }

  /// Which way the cash moved. Only meaningful on a settlement.
  bool get isIncoming => direction == SettlementDirection.moneyIn;

  /// Which way the debt runs — what the row is coloured by.
  bool get isReceivable => isSettlement ? isIncoming : (txnType?.isReceivable ?? true);

  String get label => isTransfer
      ? transferLabel(transferRole, transferCounterpartyName)
      : isOpening
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

/// public.person_opening — what an account was carried in with (0019).
///
/// Its own section on the person screen, never a row in the timeline. It is
/// still a transaction underneath, so it still counts towards [PersonBalance]
/// exactly as it always has; what changed is that it is no longer presented as
/// something that happened on a particular Tuesday, and it can no longer be
/// settled as an individual transaction.
class PersonOpening {
  const PersonOpening({
    required this.transactionId,
    required this.signedMinor,
    required this.amountMinor,
    required this.ledgerCurrency,
    required this.entryAmountMinor,
    required this.entryCurrency,
    required this.baseCurrency,
    required this.entryDate,
    required this.createdAt,
    this.amountBaseMinor,
    this.enteredAmountMinor,
    this.enteredCurrency,
    this.exchangeRateE9,
    this.exchangeRateSource,
    this.conversionMode,
    this.autoConvertedAmountMinor,
    this.note,
    this.settledMinor = 0,
    int? remainingMinor,
    this.status = SettlementStatus.open,
  }) : _remainingMinor = remainingMinor;

  final String transactionId;

  /// Positive when they owe the user, negative when the user owes them.
  /// Agrees with [PersonBalance.openingMinor] to the minor unit.
  final int signedMinor;

  /// The same figure unsigned, in the account's ledger currency.
  final int amountMinor;
  final String ledgerCurrency;

  /// What was actually entered, and in what. The headline figure.
  final int entryAmountMinor;
  final String entryCurrency;

  /// Its value in the workspace currency. Null when no rate is known.
  final int? amountBaseMinor;
  final String baseCurrency;

  final int? enteredAmountMinor;
  final String? enteredCurrency;
  final int? exchangeRateE9;
  final String? exchangeRateSource;
  final String? conversionMode;
  final int? autoConvertedAmountMinor;

  final String entryDate;
  final String createdAt;
  final String? note;

  /// Where the opening balance's OWN settlement stands (db/migrations/0021).
  ///
  /// An opening balance is settled through its own action, not through the row
  /// action the regular transactions use — two sections, two settlement paths,
  /// one screen. These come from the same FIFO allocator every other row reads.
  final int settledMinor;
  final int? _remainingMinor;
  final SettlementStatus status;

  /// What is left of it. Falls back to the whole amount against a database
  /// older than 0021, where nothing had been settled against it by this path.
  int get remainingMinor => _remainingMinor ?? amountMinor;

  /// True while there is still something to settle.
  bool get isOutstanding => remainingMinor > 0;

  /// True when a human typed the rate this was converted at (upgrade 45).
  bool get isManualRate => rateIsManual(exchangeRateSource);
  bool get isManualConversion => conversionMode == 'manual';

  /// True when the person owed the user at the moment the account opened.
  bool get isReceivable => signedMinor >= 0;

  factory PersonOpening.fromJson(Map<String, dynamic> json) => PersonOpening(
        // `transaction_id` on `opening`, and — before db/migrations/0022 — `id`
        // on a row of `opening_history`. A blunt `as String` on the first key
        // was the whole of the "That account could not be loaded." bug: history
        // is empty until the user edits an opening balance for the first time,
        // so the cast never ran until the moment it started throwing on every
        // load of that person. 0022 makes the two payloads the same shape; this
        // still reads either, so an older database does not break a newer app.
        transactionId: _str(json['transaction_id']) ?? _str(json['id']) ?? '',
        signedMinor: _int(json['signed_minor']),
        amountMinor: _int(json['amount_minor']),
        ledgerCurrency: (json['ledger_currency'] as String?) ?? kFallbackCurrency,
        entryAmountMinor: json['entry_amount_minor'] == null
            ? _int(json['amount_minor'])
            : _int(json['entry_amount_minor']),
        entryCurrency: (json['entry_currency'] as String?) ??
            (json['ledger_currency'] as String?) ??
            kFallbackCurrency,
        amountBaseMinor:
            json['amount_base_minor'] == null ? null : _int(json['amount_base_minor']),
        baseCurrency: (json['base_currency'] as String?) ??
            (json['ledger_currency'] as String?) ??
            kFallbackCurrency,
        enteredAmountMinor:
            json['entered_amount_minor'] == null ? null : _int(json['entered_amount_minor']),
        enteredCurrency: _str(json['entered_currency']),
        exchangeRateE9:
            json['exchange_rate_e9'] == null ? null : _int(json['exchange_rate_e9']),
        exchangeRateSource: _str(json['exchange_rate_source']),
        conversionMode: _str(json['conversion_mode']),
        autoConvertedAmountMinor: json['auto_converted_amount_minor'] == null
            ? null
            : _int(json['auto_converted_amount_minor']),
        entryDate: (json['entry_date'] as String?) ?? '',
        createdAt: (json['created_at'] as String?) ?? '',
        note: _str(json['note']),
        settledMinor: json['settled_minor'] == null ? 0 : _int(json['settled_minor']),
        remainingMinor:
            json['remaining_minor'] == null ? null : _int(json['remaining_minor']),
        status: SettlementStatus.parse(json['status']) ?? SettlementStatus.open,
      );
}

/// public.transfers — one movement of money between two people (0020).
///
/// Three amounts, because a cross-currency transfer has three: what the user
/// typed, what left the source in its own denomination, and what reached the
/// destination in its own. For a single-currency transfer all three are the
/// same number, which the database enforces with a CHECK constraint.
class Transfer {
  const Transfer({
    required this.id,
    required this.fromPersonId,
    required this.toPersonId,
    required this.transferDate,
    required this.entryAmountMinor,
    required this.entryCurrency,
    required this.fromAmountMinor,
    required this.fromCurrency,
    required this.toAmountMinor,
    required this.toCurrency,
    required this.isVoid,
    this.note,
    this.entryRateE9,
    this.exchangeRateE9,
    this.exchangeRateSource,
    this.conversionMode,
    this.autoConvertedAmountMinor,
  });

  final String id;
  final String fromPersonId;
  final String toPersonId;
  final String transferDate;
  final String? note;

  final int entryAmountMinor;
  final String entryCurrency;
  final int fromAmountMinor;
  final String fromCurrency;
  final int toAmountMinor;
  final String toCurrency;

  /// entry currency -> source ledger currency. Null when they are the same.
  final int? entryRateE9;

  /// source ledger currency -> destination ledger currency.
  final int? exchangeRateE9;
  final String? exchangeRateSource;
  final String? conversionMode;
  final int? autoConvertedAmountMinor;

  final bool isVoid;

  /// True when the two sides are in different currencies, and therefore when
  /// the stored rate is what links them.
  bool get isConverted => fromCurrency != toCurrency;

  factory Transfer.fromJson(Map<String, dynamic> json) => Transfer(
        id: json['id'] as String,
        fromPersonId: json['from_person_id'] as String,
        toPersonId: json['to_person_id'] as String,
        transferDate: (json['transfer_date'] as String?) ?? '',
        note: _str(json['note']),
        entryAmountMinor: _int(json['entry_amount_minor']),
        entryCurrency: (json['entry_currency'] as String?) ?? kFallbackCurrency,
        fromAmountMinor: _int(json['from_amount_minor']),
        fromCurrency: (json['from_currency'] as String?) ?? kFallbackCurrency,
        toAmountMinor: _int(json['to_amount_minor']),
        toCurrency: (json['to_currency'] as String?) ?? kFallbackCurrency,
        entryRateE9: json['entry_rate_e9'] == null ? null : _int(json['entry_rate_e9']),
        exchangeRateE9:
            json['exchange_rate_e9'] == null ? null : _int(json['exchange_rate_e9']),
        exchangeRateSource: _str(json['exchange_rate_source']),
        conversionMode: _str(json['conversion_mode']),
        autoConvertedAmountMinor: json['auto_converted_amount_minor'] == null
            ? null
            : _int(json['auto_converted_amount_minor']),
        isVoid: json['is_void'] as bool? ?? false,
      );
}

/// What every transfer RPC returns: the record, and both sides' balances, so
/// one round trip can reconcile two screens.
class TransferResult {
  const TransferResult({required this.transfer, this.fromBalance, this.toBalance});

  final Transfer transfer;
  final PersonBalance? fromBalance;
  final PersonBalance? toBalance;

  factory TransferResult.fromJson(Map<String, dynamic> json) => TransferResult(
        transfer: Transfer.fromJson(json['transfer'] as Map<String, dynamic>),
        fromBalance: json['from_balance'] == null
            ? null
            : PersonBalance.fromJson(
                Map<String, dynamic>.from(json['from_balance'] as Map)),
        toBalance: json['to_balance'] == null
            ? null
            : PersonBalance.fromJson(Map<String, dynamic>.from(json['to_balance'] as Map)),
      );
}

/// public.person_page()
/// One of the two positions an account holds (db/migrations/0022).
///
/// `person_page()` states both outright — the cash-in-hand position under
/// `regular`, the opening book's under `opening_position` — so that no client
/// subtracts one from the other and no two clients can disagree about which is
/// which. Every figure here is the database's; this class does no arithmetic.
class PositionSplit {
  const PositionSplit({
    required this.currency,
    required this.baseCurrency,
    required this.positionMinor,
    this.positionBaseMinor,
    this.receivableMinor = 0,
    this.payableMinor = 0,
    this.settledMinor = 0,
    this.creditMinor = 0,
    this.debitMinor = 0,
    this.entryCount = 0,
  });

  final String currency;
  final String baseCurrency;

  /// Signed: positive when they owe the user, negative when the user owes them.
  final int positionMinor;
  final int? positionBaseMinor;

  final int receivableMinor;
  final int payableMinor;
  final int settledMinor;
  final int creditMinor;
  final int debitMinor;

  /// Rows behind this position. Only meaningful for the opening book, where
  /// zero means the account has no opening balance at all.
  final int entryCount;

  bool get isReceivable => positionMinor >= 0;
  bool get isEmpty => positionMinor == 0 && entryCount == 0;

  factory PositionSplit.fromJson(
    Map<String, dynamic> json, {
    required String fallbackCurrency,
    required String fallbackBaseCurrency,
  }) =>
      PositionSplit(
        currency: (json['currency'] as String?) ?? fallbackCurrency,
        baseCurrency: (json['base_currency'] as String?) ?? fallbackBaseCurrency,
        positionMinor: _int(json['position']),
        positionBaseMinor:
            json['position_base'] == null ? null : _int(json['position_base']),
        receivableMinor: _int(json['receivable']),
        payableMinor: _int(json['payable']),
        settledMinor: _int(json['settled']),
        creditMinor: _int(json['credit']),
        debitMinor: _int(json['debit']),
        entryCount: _int(json['entry_count']),
      );

  /// What an older database gives us: the balance row, split the only way it
  /// can be. Keeps the screen honest against a backend that predates 0022
  /// rather than showing two figures it cannot actually tell apart.
  factory PositionSplit.fromBalance(
    PersonBalance balance, {
    required bool opening,
  }) =>
      PositionSplit(
        currency: balance.currency,
        baseCurrency: balance.baseCurrency,
        positionMinor:
            opening ? balance.openingNetMinor : balance.cashInHandMinor,
        positionBaseMinor:
            opening ? balance.openingNetBase : balance.cashInHandBase,
        receivableMinor:
            opening ? balance.openingReceivable : balance.regularReceivable,
        payableMinor: opening ? balance.openingPayable : balance.regularPayable,
        settledMinor: opening
            ? balance.openingSettledTotal
            : balance.regularSettledTotal,
        entryCount: opening ? balance.openingEntryCount : balance.transactionCount,
      );
}

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
    this.opening,
    this.openingHistory = const [],
    this.openingActivity = const [],
    PositionSplit? regular,
    PositionSplit? openingPosition,
  })  : _regular = regular,
        _openingPosition = openingPosition;

  final Person person;
  final PersonBalance balance;

  final PositionSplit? _regular;
  final PositionSplit? _openingPosition;

  /// The account's regular trading position — its cash in hand. Never contains
  /// the opening balance (db/migrations/0022).
  PositionSplit get regular =>
      _regular ?? PositionSplit.fromBalance(balance, opening: false);

  /// The opening book's position, on its own. Shown beside [regular], never
  /// inside it, and never added to it on screen.
  PositionSplit get openingPosition =>
      _openingPosition ?? PositionSplit.fromBalance(balance, opening: true);

  /// Credits, debits and settlements recorded against the opening balance.
  /// These are deliberately absent from [timeline]: they are not regular
  /// transactions and must never be shown among them.
  final List<TimelineEntry> openingActivity;

  /// The same page with a longer timeline, for a statement that pages through
  /// every row rather than showing one screenful. Every other figure is
  /// unchanged, because every other figure is the whole account's already.
  PersonPage withTimeline(List<TimelineEntry> rows) => PersonPage(
        person: person,
        balance: balance,
        timeline: rows,
        timelineTotal: timelineTotal,
        openTransactions: openTransactions,
        currency: currency,
        defaultCurrency: defaultCurrency,
        baseCurrency: baseCurrency,
        opening: opening,
        openingHistory: openingHistory,
        openingActivity: openingActivity,
        regular: _regular,
        openingPosition: _openingPosition,
      );

  /// The opening balance, in its own section (db/migrations/0019). Null when
  /// the account has none — which is not the same as zero and reads
  /// differently.
  final PersonOpening? opening;

  /// Opening balances that were replaced. They affect no balance.
  final List<PersonOpening> openingHistory;

  /// Regular activity only: credits, debits, settlements and transfer legs.
  /// The opening balance is deliberately not among them.
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
        // Absent against a database older than 0019, where the opening balance
        // is still one of the timeline rows and this screen renders as before.
        opening: json['opening'] == null
            ? null
            : PersonOpening.fromJson(Map<String, dynamic>.from(json['opening'] as Map)),
        openingHistory: [
          for (final row in (json['opening_history'] as List? ?? []))
            PersonOpening.fromJson(Map<String, dynamic>.from(row as Map)),
        ],
        openingActivity: [
          for (final entry in (json['opening_activity'] as List? ?? []))
            TimelineEntry.fromJson(Map<String, dynamic>.from(entry as Map)),
        ],
        regular: json['regular'] == null
            ? null
            : PositionSplit.fromJson(
                Map<String, dynamic>.from(json['regular'] as Map),
                fallbackCurrency:
                    (json['currency'] as String?) ?? kFallbackCurrency,
                fallbackBaseCurrency: (json['base_currency'] as String?) ??
                    (json['currency'] as String?) ??
                    kFallbackCurrency,
              ),
        openingPosition: json['opening_position'] == null
            ? null
            : PositionSplit.fromJson(
                Map<String, dynamic>.from(json['opening_position'] as Map),
                fallbackCurrency:
                    (json['currency'] as String?) ?? kFallbackCurrency,
                fallbackBaseCurrency: (json['base_currency'] as String?) ??
                    (json['currency'] as String?) ??
                    kFallbackCurrency,
              ),
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
    int? entryAmountMinor,
    String? entryCurrency,
    this.amountBaseMinor,
    this.baseCurrency,
    this.isOpening = false,
    this.enteredAmountMinor,
    this.enteredCurrency,
    this.exchangeRateE9,
    this.exchangeRateSource,
    this.conversionMode,
    this.autoConvertedAmountMinor,
  })  : _entryAmountMinor = entryAmountMinor,
        _entryCurrency = entryCurrency;

  final String id;
  final String personId;
  final String personName;
  final bool settlementIncoming;
  final bool isSettlement;

  /// What the user actually entered, and in what (db/migrations/0017).
  ///
  /// [amountMinor] is denominated in the PERSON's ledger currency, so a USD 40
  /// entry against a rupee account is stored as rupees. These two hold the
  /// dollars — the figure the user typed and recognises, and therefore the one
  /// to show. They fall back to the ledger pair when no conversion happened.
  final int? _entryAmountMinor;
  final String? _entryCurrency;

  /// The row's value in the workspace currency. Supplementary: it goes BESIDE
  /// the entered amount, never instead of it. Null when no rate is cached.
  final int? amountBaseMinor;
  final String? baseCurrency;

  int get entryAmountMinor => _entryAmountMinor ?? amountMinor;
  String get entryCurrency => _entryCurrency ?? currency;

  /// Whether the base equivalent says anything the primary figure does not.
  bool get showsBaseEquivalent =>
      amountBaseMinor != null && baseCurrency != null && baseCurrency != entryCurrency;

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

  /// See [TimelineEntry.exchangeRateSource].
  final String? exchangeRateSource;

  /// See [TimelineEntry.conversionMode].
  final String? conversionMode;
  final int? autoConvertedAmountMinor;

  bool get isManualConversion => conversionMode == 'manual';
  bool get isManualRate => rateIsManual(exchangeRateSource);

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
      // What was actually entered, and its base-currency equivalent (0017).
      // Absent against an older database, where the ledger pair was the whole
      // truth anyway — the getters fall back to it.
      entryAmountMinor:
          json['entry_amount_minor'] == null ? null : _int(json['entry_amount_minor']),
      entryCurrency: _str(json['entry_currency']),
      amountBaseMinor:
          json['amount_base_minor'] == null ? null : _int(json['amount_base_minor']),
      baseCurrency: _str(json['base_currency']),
      isOpening: json['is_opening'] as bool? ?? false,
      enteredAmountMinor:
          json['entered_amount_minor'] == null ? null : _int(json['entered_amount_minor']),
      enteredCurrency: _str(json['entered_currency']),
      exchangeRateE9:
          json['exchange_rate_e9'] == null ? null : _int(json['exchange_rate_e9']),
      exchangeRateSource: _str(json['exchange_rate_source']),
      conversionMode: _str(json['conversion_mode']),
      autoConvertedAmountMinor: json['auto_converted_amount_minor'] == null
          ? null
          : _int(json['auto_converted_amount_minor']),
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

/// One currency's standing position, in that currency (db/migrations/0015).
///
/// Never converted and never summed with another row: [OwnerSummary] is the
/// base-currency answer, and this is the same money read in the denomination it
/// was actually entered in.
class CurrencyTotals {
  const CurrencyTotals({
    required this.currency,
    required this.baseCurrency,
    required this.grossCredit,
    required this.grossDebit,
    required this.grossSettled,
    required this.netPosition,
    required this.entryCount,
    required this.peopleCount,
    this.netBaseMinor,
  });

  /// The currency the entries were actually made in — not the denomination of
  /// the accounts they landed in (db/migrations/0017).
  final String currency;

  /// The workspace currency the equivalent below is stated in.
  final String baseCurrency;

  final int grossCredit;
  final int grossDebit;
  final int grossSettled;

  /// credit - debit, in [currency]. Never mixed with another currency.
  final int netPosition;

  /// [netPosition] converted to [baseCurrency] by the engine's own converter.
  /// Supplementary — the figure above is the real one. Null means no rate is
  /// cached, which is "not known", never zero.
  final int? netBaseMinor;

  final int entryCount;
  final int peopleCount;

  /// Whether the equivalent says anything the primary figure does not.
  bool get showsBaseEquivalent => netBaseMinor != null && baseCurrency != currency;

  factory CurrencyTotals.fromJson(Map<String, dynamic> json) => CurrencyTotals(
        currency: (json['currency'] as String?) ?? kFallbackCurrency,
        baseCurrency: (json['base_currency'] as String?) ?? kFallbackCurrency,
        grossCredit: _int(json['gross_credit']),
        grossDebit: _int(json['gross_debit']),
        grossSettled: _int(json['gross_settled']),
        netPosition: _int(json['net_position']),
        netBaseMinor: json['net_base_minor'] == null ? null : _int(json['net_base_minor']),
        entryCount: _int(json['entry_count']),
        peopleCount: _int(json['people_count']),
      );
}

/// Today's movement in one entry currency (db/migrations/0017).
class CurrencyToday {
  const CurrencyToday({
    required this.currency,
    required this.baseCurrency,
    required this.credit,
    required this.debit,
    required this.settled,
    required this.count,
    this.movedBaseMinor,
  });

  final String currency;
  final String baseCurrency;
  final int credit;
  final int debit;
  final int settled;
  final int count;

  /// Everything that moved today in this currency, converted to base.
  final int? movedBaseMinor;

  /// Everything that moved today in this currency, whichever way it went.
  int get moved => credit + debit + settled;

  factory CurrencyToday.fromJson(Map<String, dynamic> json) => CurrencyToday(
        currency: (json['currency'] as String?) ?? kFallbackCurrency,
        baseCurrency: (json['base_currency'] as String?) ?? kFallbackCurrency,
        credit: _int(json['credit']),
        debit: _int(json['debit']),
        settled: _int(json['settled']),
        count: _int(json['count']),
        movedBaseMinor:
            json['moved_base_minor'] == null ? null : _int(json['moved_base_minor']),
      );
}

/// One workspace-level total, in the workspace currency (db/migrations/0022).
///
/// The dashboard shows two of these and never one: `Cash in hand` is the
/// consolidated regular position, `Opening balance` is the opening book's. They
/// are calculated independently by the database and add up to the net position,
/// which is what makes it safe to print both without double-counting anything.
class WorkspacePosition {
  const WorkspacePosition({
    required this.baseCurrency,
    required this.positionMinor,
    this.receivableMinor = 0,
    this.payableMinor = 0,
    this.settledMinor = 0,
    this.todayMinor = 0,
    this.todayCount = 0,
    this.peopleCount = 0,
  });

  final String baseCurrency;

  /// Signed: positive when the workspace is owed, negative when it owes.
  final int positionMinor;
  final int receivableMinor;
  final int payableMinor;
  final int settledMinor;

  /// Everything that moved today within this half of the ledger.
  final int todayMinor;
  final int todayCount;
  final int peopleCount;

  bool get isReceivable => positionMinor >= 0;

  factory WorkspacePosition.fromJson(
    Map<String, dynamic> json, {
    required String fallbackBaseCurrency,
  }) =>
      WorkspacePosition(
        baseCurrency: (json['base_currency'] as String?) ?? fallbackBaseCurrency,
        positionMinor: _int(json['position']),
        receivableMinor: _int(json['receivable']),
        payableMinor: _int(json['payable']),
        settledMinor: _int(json['settled']),
        todayMinor: _int(json['today']),
        todayCount: _int(json['today_count']),
        peopleCount: _int(json['people_count']),
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
    this.totalsByCurrency = const [],
    this.todayByCurrency = const [],
    this.cashInHand,
    this.openingTotal,
  });

  /// The consolidated regular position, converted to the workspace currency.
  /// Never contains an opening balance. Null against a database older than
  /// 0022, where the split does not exist and the screen falls back to the one
  /// figure it always had.
  final WorkspacePosition? cashInHand;

  /// The opening book's position, calculated independently and shown beside
  /// [cashInHand] — never inside it.
  final WorkspacePosition? openingTotal;

  final OwnerSummary summary;
  final TodayTotals today;

  /// Only currencies that carry entries. Empty on a workspace with none, and
  /// empty against a database that has not run 0015 — in which case the client
  /// renders the base-currency dashboard it always did.
  final List<CurrencyTotals> totalsByCurrency;
  final List<CurrencyToday> todayByCurrency;

  final List<ActivityItem> recentActivity;
  final List<PersonBalance> peopleWithBalance;
  final String currency;

  /// What the headline totals are converted into. The same as [currency] today,
  /// and named separately because they answer different questions.
  final String baseCurrency;
  final String name;

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    final profile = (json['profile'] as Map<String, dynamic>?) ?? const {};
    final base = (json['base_currency'] as String?) ??
        (profile['currency'] as String?) ??
        kFallbackCurrency;
    return Dashboard(
      summary: OwnerSummary.fromJson(json['summary'] as Map<String, dynamic>),
      cashInHand: json['cash_in_hand'] == null
          ? null
          : WorkspacePosition.fromJson(
              Map<String, dynamic>.from(json['cash_in_hand'] as Map),
              fallbackBaseCurrency: base,
            ),
      openingTotal: json['opening'] == null
          ? null
          : WorkspacePosition.fromJson(
              Map<String, dynamic>.from(json['opening'] as Map),
              fallbackBaseCurrency: base,
            ),
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
      totalsByCurrency: [
        for (final entry in (json['totals_by_currency'] as List? ?? []))
          CurrencyTotals.fromJson(entry as Map<String, dynamic>),
      ],
      todayByCurrency: [
        for (final entry in (json['today_by_currency'] as List? ?? []))
          CurrencyToday.fromJson(entry as Map<String, dynamic>),
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
