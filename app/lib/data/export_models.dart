/// The shape of `export_workspace()` and `export_entries()` (0025).
///
/// Mirrors `web/src/lib/export/types.ts` key for key. The writers — CSV, JSON
/// and the PDF — all read these, so a change to the SQL is a compile error
/// here rather than a wrong column in a file someone has already saved.
library;

/// The one schema version every export file carries.
const int kExportSchemaVersion = 1;

class ExportFilters {
  const ExportFilters({
    this.from,
    this.to,
    this.personId,
    this.currency,
    this.kinds,
    this.scope = 'all',
    this.includeVoid = false,
  });

  factory ExportFilters.fromJson(Map<String, dynamic> json) => ExportFilters(
    from: json['from'] as String?,
    to: json['to'] as String?,
    personId: json['person_id'] as String?,
    currency: json['currency'] as String?,
    kinds: (json['kinds'] as List?)?.map((e) => e.toString()).toList(),
    scope: (json['scope'] as String?) ?? 'all',
    includeVoid: json['include_void'] == true,
  );

  final String? from;
  final String? to;
  final String? personId;
  final String? currency;
  final List<String>? kinds;

  /// all | regular | opening.
  final String scope;
  final bool includeVoid;

  Map<String, dynamic> toJson() => {
    'from': from,
    'to': to,
    'person_id': personId,
    'currency': currency,
    'kinds': kinds,
    'scope': scope,
    'include_void': includeVoid,
  };

  /// Query parameters for the two RPCs, named exactly as they are declared.
  Map<String, dynamic> toParams() => {
    'p_from': from,
    'p_to': to,
    'p_person_id': personId,
    'p_currency': currency,
    'p_kinds': (kinds == null || kinds!.isEmpty) ? null : kinds,
    'p_scope': scope,
    'p_include_void': includeVoid,
  };

  /// The filter contract for an Activity export.
  ///
  /// Two independent choices, both expressed in what `export_entries()` already
  /// accepts: the category as [kinds] (null for Everything), and the dates as
  /// [from]/[to] (equal for one day, both null for the whole feed).
  ///
  /// `scope` stays `all` because the Activity feed includes the opening book,
  /// and voided history stays out because `activity_page()` excludes it too —
  /// the export must not show what the screen does not.
  ///
  /// Mirrors `activityExportRequest()` in `web/src/lib/export/activity.ts`.
  factory ExportFilters.activity({
    List<String>? kinds,
    String? from,
    String? to,
  }) => ExportFilters(from: from, to: to, kinds: kinds, scope: 'all');

  /// What this export holds, in the words a sheet can show before generating it.
  String get description {
    final parts = <String>[];
    if (from != null || to != null) {
      parts.add('${from ?? 'the beginning'} to ${to ?? 'today'}');
    }
    if (currency != null) parts.add('entered in $currency');
    if (kinds != null && kinds!.isNotEmpty) parts.add(kinds!.join(', '));
    if (scope == 'opening') parts.add('opening balances only');
    if (scope == 'regular') parts.add('excluding opening balances');
    if (includeVoid) parts.add('including voided history');
    return parts.isEmpty ? 'Everything' : parts.join(' · ');
  }

  /// Value equality, because a Riverpod family keys on it: two identical filter
  /// sets must be one request, not two.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportFilters &&
          other.from == from &&
          other.to == to &&
          other.personId == personId &&
          other.currency == currency &&
          other.scope == scope &&
          other.includeVoid == includeVoid &&
          _sameKinds(other.kinds, kinds);

  @override
  int get hashCode => Object.hash(
    from,
    to,
    personId,
    currency,
    scope,
    includeVoid,
    kinds == null ? null : Object.hashAll(kinds!),
  );

  static bool _sameKinds(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  ExportFilters copyWith({
    String? from,
    String? to,
    String? personId,
    String? currency,
    List<String>? kinds,
    String? scope,
    bool? includeVoid,
    bool clearDates = false,
    bool clearPerson = false,
    bool clearCurrency = false,
    bool clearKinds = false,
  }) => ExportFilters(
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    personId: clearPerson ? null : (personId ?? this.personId),
    currency: clearCurrency ? null : (currency ?? this.currency),
    kinds: clearKinds ? null : (kinds ?? this.kinds),
    scope: scope ?? this.scope,
    includeVoid: includeVoid ?? this.includeVoid,
  );
}

class ExportCurrency {
  const ExportCurrency({
    required this.code,
    required this.name,
    required this.symbol,
    required this.decimals,
  });

  factory ExportCurrency.fromJson(Map<String, dynamic> json) => ExportCurrency(
    code: json['code'] as String,
    name: (json['name'] as String?) ?? json['code'] as String,
    symbol: (json['symbol'] as String?) ?? '',
    decimals: (json['decimals'] as num?)?.toInt() ?? 2,
  );

  final String code;
  final String name;
  final String symbol;

  /// ISO 4217 minor-unit exponent: what an integer amount in this currency means.
  final int decimals;

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'symbol': symbol,
    'decimals': decimals,
  };
}

class ExportCounts {
  const ExportCounts({
    required this.people,
    required this.entries,
    required this.transactions,
    required this.settlements,
    required this.transfers,
    required this.opening,
    required this.voided,
  });

  factory ExportCounts.fromJson(Map<String, dynamic> json) => ExportCounts(
    people: (json['people'] as num?)?.toInt() ?? 0,
    entries: (json['entries'] as num?)?.toInt() ?? 0,
    transactions: (json['transactions'] as num?)?.toInt() ?? 0,
    settlements: (json['settlements'] as num?)?.toInt() ?? 0,
    transfers: (json['transfers'] as num?)?.toInt() ?? 0,
    opening: (json['opening'] as num?)?.toInt() ?? 0,
    voided: (json['voided'] as num?)?.toInt() ?? 0,
  );

  final int people;
  final int entries;
  final int transactions;
  final int settlements;
  final int transfers;
  final int opening;
  final int voided;

  Map<String, dynamic> toJson() => {
    'people': people,
    'entries': entries,
    'transactions': transactions,
    'settlements': settlements,
    'transfers': transfers,
    'opening': opening,
    'voided': voided,
  };
}

/// `export_workspace()` — the header of an export.
class ExportHeader {
  const ExportHeader({
    required this.schemaVersion,
    required this.generator,
    required this.exportedAt,
    required this.filters,
    required this.workspace,
    required this.summary,
    required this.totalsByCurrency,
    required this.currencies,
    required this.people,
    required this.counts,
  });

  factory ExportHeader.fromJson(Map<String, dynamic> json) => ExportHeader(
    schemaVersion: (json['schema_version'] as num?)?.toInt() ?? kExportSchemaVersion,
    generator: (json['generator'] as String?) ?? 'accounic',
    exportedAt: (json['exported_at'] as String?) ?? '',
    filters: ExportFilters.fromJson(
      Map<String, dynamic>.from((json['filters'] as Map?) ?? const {}),
    ),
    workspace: json['workspace'] == null
        ? const {}
        : Map<String, dynamic>.from(json['workspace'] as Map),
    summary: json['summary'] == null
        ? const {}
        : Map<String, dynamic>.from(json['summary'] as Map),
    totalsByCurrency: ((json['totals_by_currency'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    currencies: ((json['currencies'] as List?) ?? const [])
        .map((e) => ExportCurrency.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    people: ((json['people'] as List?) ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList(),
    counts: ExportCounts.fromJson(
      Map<String, dynamic>.from((json['counts'] as Map?) ?? const {}),
    ),
  );

  final int schemaVersion;
  final String generator;
  final String exportedAt;
  final ExportFilters filters;

  /// The profile: the owner's own name, business name and contact details.
  final Map<String, dynamic> workspace;

  /// The `owner_summary` row, exactly as the engine states it.
  final Map<String, dynamic> summary;

  /// The workspace position per entry currency, as `dashboard()` states it.
  /// Deliberately NOT narrowed by the export's filters — it is the position,
  /// not a total of the slice — and every writer labels it as such.
  final List<Map<String, dynamic>> totalsByCurrency;
  final List<ExportCurrency> currencies;

  /// Each person with their `person_balances` and `person_opening` rows.
  final List<Map<String, dynamic>> people;
  final ExportCounts counts;

  String get workspaceName =>
      (workspace['business_name'] as String?)?.trim().isNotEmpty == true
      ? workspace['business_name'] as String
      : ((workspace['name'] as String?) ?? 'Accounic');

  String get baseCurrency => (workspace['base_currency'] as String?) ?? 'INR';

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'generator': generator,
    'exported_at': exportedAt,
    'filters': filters.toJson(),
    'workspace': workspace,
    'summary': summary,
    'totals_by_currency': totalsByCurrency,
    'currencies': currencies.map((c) => c.toJson()).toList(),
    'people': people,
    'counts': counts.toJson(),
  };
}

/// One row of the ledger, as `export_entries()` states it.
class ExportEntry {
  const ExportEntry({
    required this.id,
    required this.kind,
    required this.type,
    required this.direction,
    required this.date,
    required this.personId,
    required this.personName,
    required this.note,
    required this.isVoid,
    required this.scope,
    required this.openingRole,
    required this.transferId,
    required this.transferRole,
    required this.entryAmountMinor,
    required this.entryCurrency,
    required this.amountMinor,
    required this.ledgerCurrency,
    required this.amountBaseMinor,
    required this.baseCurrency,
    required this.exchangeRateE9,
    required this.exchangeRateSource,
    required this.conversionMode,
    required this.settledMinor,
    required this.remainingMinor,
    required this.settlementStatus,
    required this.createdAt,
    required this.raw,
  });

  factory ExportEntry.fromJson(Map<String, dynamic> json) => ExportEntry(
    id: json['id'] as String,
    kind: (json['kind'] as String?) ?? 'transaction',
    type: json['type'] as String?,
    direction: json['direction'] as String?,
    date: (json['date'] as String?) ?? '',
    personId: (json['person_id'] as String?) ?? '',
    personName: json['person_name'] as String?,
    note: json['note'] as String?,
    isVoid: json['is_void'] == true,
    scope: (json['scope'] as String?) ?? 'regular',
    openingRole: json['opening_role'] as String?,
    transferId: json['transfer_id'] as String?,
    transferRole: json['transfer_role'] as String?,
    entryAmountMinor: (json['entry_amount_minor'] as num?)?.toInt() ?? 0,
    entryCurrency: (json['entry_currency'] as String?) ?? 'INR',
    amountMinor: (json['amount_minor'] as num?)?.toInt() ?? 0,
    ledgerCurrency: (json['ledger_currency'] as String?) ?? 'INR',
    amountBaseMinor: (json['amount_base_minor'] as num?)?.toInt(),
    baseCurrency: (json['base_currency'] as String?) ?? 'INR',
    exchangeRateE9: (json['exchange_rate_e9'] as num?)?.toInt(),
    exchangeRateSource: json['exchange_rate_source'] as String?,
    conversionMode: json['conversion_mode'] as String?,
    settledMinor: (json['settled_minor'] as num?)?.toInt(),
    remainingMinor: (json['remaining_minor'] as num?)?.toInt(),
    settlementStatus: json['settlement_status'] as String?,
    createdAt: (json['created_at'] as String?) ?? '',
    raw: json,
  );

  final String id;

  /// transaction | settlement.
  final String kind;

  /// credit | debit for a transaction; the settlement direction otherwise.
  final String? type;
  final String? direction;
  final String date;
  final String personId;
  final String? personName;
  final String? note;
  final bool isVoid;

  /// regular | opening — which book this row belongs to.
  final String scope;
  final String? openingRole;
  final String? transferId;
  final String? transferRole;

  /// The figure as entered, in the currency it was entered in.
  final int entryAmountMinor;
  final String entryCurrency;

  /// The same money in the account's ledger currency.
  final int amountMinor;
  final String ledgerCurrency;

  /// And in the workspace's base currency, when it could be converted.
  final int? amountBaseMinor;
  final String baseCurrency;

  final int? exchangeRateE9;
  final String? exchangeRateSource;
  final String? conversionMode;

  final int? settledMinor;
  final int? remainingMinor;
  final String? settlementStatus;
  final String createdAt;

  /// The row exactly as it arrived, so the JSON backup loses nothing this
  /// class has not thought to name.
  final Map<String, dynamic> raw;

  bool get isOpening => scope == 'opening';
  bool get isSettlement => kind == 'settlement';
}

/// One page of `export_entries()`.
class ExportEntryPage {
  const ExportEntryPage({
    required this.limit,
    required this.offset,
    required this.total,
    required this.hasMore,
    required this.entries,
  });

  factory ExportEntryPage.fromJson(Map<String, dynamic> json) => ExportEntryPage(
    limit: (json['limit'] as num?)?.toInt() ?? 0,
    offset: (json['offset'] as num?)?.toInt() ?? 0,
    total: (json['total'] as num?)?.toInt() ?? 0,
    hasMore: json['has_more'] == true,
    entries: ((json['entries'] as List?) ?? const [])
        .map((e) => ExportEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );

  final int limit;
  final int offset;
  final int total;
  final bool hasMore;
  final List<ExportEntry> entries;
}

/// A header and every entry it describes: one complete export.
class ExportBundle {
  const ExportBundle({
    required this.header,
    required this.entries,
    required this.truncated,
  });

  final ExportHeader header;
  final List<ExportEntry> entries;

  /// True when the list was cut short by the size cap rather than by a filter.
  final bool truncated;
}
