import '../data/export_models.dart';
import 'dates.dart';
import 'direction.dart';
import 'statement.dart';
import 'transfers.dart';

/// What the workspace report says, before anything is drawn (Phase 4).
///
/// The mirror of `web/src/lib/export/report.ts`, and split from the PDF for the
/// same two reasons `core/statement.dart` is: it is pure, so it can be tested
/// without a PDF reader or a font; and it is the only place the report decides
/// what to say, which is what keeps the printed figures identical to the
/// screen's.
///
///   * NOTHING IS COMPUTED HERE. The workspace position comes from
///     `owner_summary`, the per-currency positions from `dashboard()`, each
///     person's figures from `person_balances`. A report that disagreed with
///     the dashboard would be worse than no report.
///   * CURRENCY IS NEVER COLLAPSED. Positions are listed per currency and never
///     summed across them; an amount prints in the currency it was entered in,
///     with its base equivalent beside it.
///   * THE BOOKS STAY APART. Opening balances get their own block per person,
///     exactly as on the person screen.

class ReportPosition {
  const ReportPosition({
    required this.currency,
    required this.receivable,
    required this.payable,
    required this.net,
    required this.netReceivable,
    required this.cash,
    required this.opening,
  });

  final String currency;
  final String receivable;
  final String payable;
  final String net;
  final bool netReceivable;

  /// Cash in hand and the opening balance, kept apart as everywhere else.
  final String? cash;
  final String? opening;
}

class ReportPersonLine {
  const ReportPersonLine({
    required this.name,
    required this.currency,
    required this.receivable,
    required this.payable,
    required this.net,
    required this.netReceivable,
    required this.opening,
    required this.archived,
  });

  final String name;
  final String currency;
  final String receivable;
  final String payable;
  final String net;
  final bool netReceivable;
  final String? opening;
  final bool archived;
}

class ReportRow {
  const ReportRow({
    required this.date,
    required this.type,
    required this.description,
    required this.amount,
    required this.equivalent,
    required this.settlement,
    required this.isVoid,
    required this.isOpening,
    required this.isReceivable,
  });

  final String date;
  final String type;
  final String description;

  /// The amount as entered, in the currency it was entered in.
  final String amount;

  /// The base equivalent, when the entry was converted.
  final String? equivalent;

  /// `Settled`, `₹400 of ₹1,000`, or null for a row that cannot be settled.
  final String? settlement;
  final bool isVoid;
  final bool isOpening;
  final bool isReceivable;
}

class ReportSection {
  const ReportSection({
    required this.personId,
    required this.personName,
    required this.currency,
    required this.rows,
    required this.openingRows,
  });

  final String personId;
  final String personName;
  final String currency;
  final List<ReportRow> rows;
  final List<ReportRow> openingRows;

  bool get isEmpty => rows.isEmpty && openingRows.isEmpty;
}

class WorkspaceReport {
  const WorkspaceReport({
    required this.title,
    required this.workspaceName,
    required this.ownerName,
    required this.exportedAt,
    required this.period,
    required this.filters,
    required this.baseCurrency,
    required this.positions,
    required this.people,
    required this.sections,
    required this.counts,
    required this.truncated,
  });

  final String title;
  final String workspaceName;
  final String? ownerName;
  final String exportedAt;

  /// `01 Jan 2026 — 01 Sep 2026`, or `Everything to date`.
  final String period;

  /// What was asked for, in words, so the file says what it holds.
  final String filters;
  final String baseCurrency;
  final List<ReportPosition> positions;
  final List<ReportPersonLine> people;
  final List<ReportSection> sections;
  final ExportCounts counts;

  /// Set when the export hit its size cap: printed on the cover, never hidden.
  final bool truncated;
}

int _num(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String? _text(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

/// What a row is called — the same words the screen uses.
String reportRowType(ExportEntry entry) {
  if (entry.transferId != null) {
    return transferLabel(TransferRole.parse(entry.transferRole), null);
  }
  if (entry.isOpening) {
    return entry.openingRole == 'adjustment'
        ? 'Opening ${MoneyFlow.parse(entry.type).label.toLowerCase()}'
        : 'Opening balance';
  }
  if (entry.isSettlement) {
    return entry.type == 'in' ? 'Settlement received' : 'Settlement paid';
  }
  return MoneyFlow.parse(entry.type).label;
}

/// How much of a transaction is settled, in one phrase, or null.
String? reportSettlement(ExportEntry entry, StatementFormatter format) {
  if (entry.isSettlement) return null;
  final status = entry.settlementStatus;
  if (status == null) return null;
  if (status == 'settled') return 'Settled';
  if (status == 'open') return 'Open';

  final settled = format.money(entry.settledMinor ?? 0, currency: entry.ledgerCurrency);
  final total = format.money(entry.amountMinor, currency: entry.ledgerCurrency);
  return '$settled of $total';
}

ReportRow _toRow(ExportEntry entry, StatementFormatter format) {
  final converted =
      entry.entryCurrency != entry.baseCurrency && entry.amountBaseMinor != null;

  return ReportRow(
    date: statementDate(entry.date),
    type: reportRowType(entry),
    description: (entry.note ?? '').trim().isEmpty ? '—' : entry.note!.trim(),
    amount: format.money(entry.entryAmountMinor, currency: entry.entryCurrency),
    equivalent: converted
        ? format.approx(entry.amountBaseMinor!, currency: entry.baseCurrency)
        : null,
    settlement: reportSettlement(entry, format),
    isVoid: entry.isVoid,
    isOpening: entry.isOpening,
    isReceivable: entryIsReceivable(entry.type),
  );
}

ReportPersonLine _personLine(Map<String, dynamic> person, StatementFormatter format) {
  final balance = person['balance'] == null
      ? const <String, dynamic>{}
      : Map<String, dynamic>.from(person['balance'] as Map);
  final currency =
      _text(balance['currency']) ?? _text(person['ledger_currency']) ?? 'INR';
  final net = _num(balance['net_balance']);
  final opening = _num(balance['opening_net_minor']);

  return ReportPersonLine(
    name: (person['name'] as String?) ?? '—',
    currency: currency,
    receivable: format.money(
      _num(balance['outstanding_receivable']),
      currency: currency,
    ),
    payable: format.money(_num(balance['outstanding_payable']), currency: currency),
    net: format.money(net.abs(), currency: currency),
    netReceivable: net >= 0,
    opening: opening == 0 ? null : format.money(opening.abs(), currency: currency),
    archived: person['is_archived'] == true,
  );
}

List<ReportPosition> _positions(ExportHeader header, StatementFormatter format) {
  return header.totalsByCurrency.map((row) {
    final currency = _text(row['currency']) ?? header.baseCurrency;
    final net = _num(row['net']);
    final cash = row['cash'] == null
        ? null
        : Map<String, dynamic>.from(row['cash'] as Map);
    final opening = row['opening'] == null
        ? null
        : Map<String, dynamic>.from(row['opening'] as Map);

    return ReportPosition(
      currency: currency,
      receivable: format.money(_num(row['receivable']), currency: currency),
      payable: format.money(_num(row['payable']), currency: currency),
      net: format.money(net.abs(), currency: currency),
      netReceivable: net >= 0,
      cash: cash == null ? null : format.money(_num(cash['net']), currency: currency),
      opening:
          opening == null ? null : format.money(_num(opening['net']), currency: currency),
    );
  }).toList();
}

String _period(ExportFilters filters) {
  if (filters.from == null && filters.to == null) return 'Everything to date';
  final from = filters.from == null ? 'The beginning' : statementDate(filters.from!);
  final to = filters.to == null ? 'today' : statementDate(filters.to!);
  return '$from — $to';
}

String _describe(ExportFilters filters) {
  final parts = <String>[];
  if (filters.currency != null) parts.add('entered in ${filters.currency}');
  if (filters.kinds != null && filters.kinds!.isNotEmpty) {
    parts.add(filters.kinds!.join(', '));
  }
  if (filters.scope == 'opening') parts.add('opening balances only');
  if (filters.scope == 'regular') parts.add('excluding opening balances');
  if (filters.includeVoid) parts.add('including voided history');
  return parts.isEmpty ? 'Every account, every entry' : parts.join(' · ');
}

/// The whole report, ready to draw.
WorkspaceReport buildWorkspaceReport(ExportBundle bundle, StatementFormatter format) {
  final header = bundle.header;

  final byPerson = <String, List<ExportEntry>>{};
  for (final entry in bundle.entries) {
    byPerson.putIfAbsent(entry.personId, () => []).add(entry);
  }

  // Sections follow the people list, so the report is ordered the way the
  // People screen is, and a person with no entries in the period still appears
  // with their balance rather than vanishing from the file.
  final sections = header.people.map((person) {
    final id = (person['id'] as String?) ?? '';
    final rows = byPerson[id] ?? const <ExportEntry>[];
    return ReportSection(
      personId: id,
      personName: (person['name'] as String?) ?? '—',
      currency: (person['ledger_currency'] as String?) ?? header.baseCurrency,
      rows: rows.where((e) => !e.isOpening).map((e) => _toRow(e, format)).toList(),
      openingRows: rows.where((e) => e.isOpening).map((e) => _toRow(e, format)).toList(),
    );
  }).toList();

  return WorkspaceReport(
    title: 'Accounting export',
    workspaceName: header.workspaceName,
    ownerName: _text(header.workspace['name']),
    exportedAt: header.exportedAt,
    period: _period(header.filters),
    filters: _describe(header.filters),
    baseCurrency: header.baseCurrency,
    positions: _positions(header, format),
    people: header.people.map((p) => _personLine(p, format)).toList(),
    sections: sections,
    counts: header.counts,
    truncated: bundle.truncated,
  );
}
