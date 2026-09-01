import { entryLabel } from '@/lib/direction';
import { transferLabel } from '@/lib/transfers';
import { statementDate } from '@/lib/dates';

import type { ExportBundle, ExportEntry, ExportPerson } from '@/lib/export/types';

/**
 * What the workspace report says, before anything is drawn (Phase 4).
 *
 * The same split as `lib/pdf/rows.ts`, for the same two reasons: it is pure, so
 * it can be tested without a PDF reader or a font file; and it is the only
 * place the report decides what to say, which is what keeps the printed figures
 * identical to the screen's.
 *
 * The rules it obeys are the product's, not the page's:
 *
 *   * NOTHING IS COMPUTED. Every number here came from the database — the
 *     workspace position from `owner_summary`, the per-currency positions from
 *     `dashboard()`, each person's figures from `person_balances`. A report
 *     that disagreed with the dashboard would be worse than no report.
 *   * CURRENCY IS NEVER COLLAPSED. Positions are listed per currency, side by
 *     side, and never summed across them. An amount is printed in the currency
 *     it was entered in, with its base equivalent beside it when there is one.
 *   * THE THREE BOOKS STAY APART. Opening balances are their own section, as
 *     they are on the person screen, and settlements are labelled as
 *     settlements rather than folded in as negative transactions.
 *
 * Mirrored by `app/lib/core/export_report.dart`.
 */

export interface ReportFormatter {
  money(minor: number, currency: string | null | undefined): string;
  approx(minor: number, currency: string | null | undefined): string;
}

export interface ReportPosition {
  currency: string;
  /** Money owed to the user, in that currency. */
  receivable: string;
  /** Money the user owes. */
  payable: string;
  /** The net of the two, and whether it is in the user's favour. */
  net: string;
  netReceivable: boolean;
  /** Cash in hand and the opening balance, kept apart as everywhere else. */
  cash: string | null;
  opening: string | null;
}

export interface ReportPersonLine {
  name: string;
  currency: string;
  receivable: string;
  payable: string;
  net: string;
  netReceivable: boolean;
  opening: string | null;
  archived: boolean;
}

export interface ReportRow {
  date: string;
  type: string;
  description: string;
  /** The amount as entered, in the currency it was entered in. */
  amount: string;
  /** The base equivalent, when the entry was converted. */
  equivalent: string | null;
  /** `Settled`, `₹400 of ₹1,000`, or null for a row that cannot be settled. */
  settlement: string | null;
  isVoid: boolean;
  isOpening: boolean;
}

export interface ReportSection {
  personId: string;
  personName: string;
  currency: string;
  rows: ReportRow[];
  openingRows: ReportRow[];
}

export interface WorkspaceReport {
  title: string;
  workspaceName: string;
  ownerName: string | null;
  exportedAt: string;
  /** `1 Jan 2026 — 1 Sep 2026`, or `Everything to date`. */
  period: string;
  /** What was asked for, in words, so the file says what it holds. */
  filters: string;
  baseCurrency: string;
  positions: ReportPosition[];
  people: ReportPersonLine[];
  sections: ReportSection[];
  counts: { people: number; entries: number; transactions: number; settlements: number };
  /** Set when the export hit its size cap: printed on the cover, not hidden. */
  truncated: boolean;
}

function num(value: unknown): number {
  const parsed = typeof value === 'number' ? value : Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed : 0;
}

function text(value: unknown): string | null {
  return typeof value === 'string' && value.trim() !== '' ? value : null;
}

/** What a row is called — the same words the screen uses. */
export function reportRowType(entry: ExportEntry): string {
  if (entry.transfer_id) {
    return transferLabel(entry.transfer_role as 'source' | 'destination' | null, null);
  }
  if (entry.scope === 'opening') {
    return entry.opening_role === 'adjustment'
      ? `Opening ${entryLabel('transaction', entry.type ?? 'credit').toLowerCase()}`
      : 'Opening balance';
  }
  return entryLabel(entry.kind, entry.type ?? '');
}

/** How much of a transaction is settled, in one phrase, or null. */
export function reportSettlement(entry: ExportEntry, format: ReportFormatter): string | null {
  if (entry.kind !== 'transaction') return null;
  if (entry.settlement_status === null || entry.settlement_status === undefined) return null;
  if (entry.settlement_status === 'settled') return 'Settled';
  if (entry.settlement_status === 'open') return 'Open';

  const settled = num(entry.settled_minor);
  return `${format.money(settled, entry.ledger_currency)} of ${format.money(
    num(entry.amount_minor),
    entry.ledger_currency,
  )}`;
}

function toRow(entry: ExportEntry, format: ReportFormatter): ReportRow {
  const converted =
    entry.entry_currency !== entry.base_currency && entry.amount_base_minor !== null;

  return {
    date: statementDate(entry.date),
    type: reportRowType(entry),
    description: (entry.note ?? '').trim() || '—',
    amount: format.money(entry.entry_amount_minor, entry.entry_currency),
    equivalent: converted ? format.approx(num(entry.amount_base_minor), entry.base_currency) : null,
    settlement: reportSettlement(entry, format),
    isVoid: entry.is_void,
    isOpening: entry.scope === 'opening',
  };
}

function personLine(person: ExportPerson, format: ReportFormatter): ReportPersonLine {
  const balance = person.balance ?? {};
  const currency = (text(balance['currency']) ?? person.ledger_currency) as string;
  const net = num(balance['net_balance']);
  const opening = num(balance['opening_net_minor']);

  return {
    name: person.name,
    currency,
    receivable: format.money(num(balance['outstanding_receivable']), currency),
    payable: format.money(num(balance['outstanding_payable']), currency),
    net: format.money(Math.abs(net), currency),
    netReceivable: net >= 0,
    opening: opening === 0 ? null : format.money(Math.abs(opening), currency),
    archived: person.is_archived,
  };
}

function positions(bundle: ExportBundle, format: ReportFormatter): ReportPosition[] {
  const totals = bundle.header.totals_by_currency;
  if (!Array.isArray(totals)) return [];

  return totals.map((raw) => {
    const row = raw as Record<string, unknown>;
    const currency = (text(row['currency']) ?? bundle.header.workspace?.base_currency ?? 'INR') as string;
    const net = num(row['net']);
    const cash = row['cash'] as Record<string, unknown> | undefined;
    const opening = row['opening'] as Record<string, unknown> | undefined;

    return {
      currency,
      receivable: format.money(num(row['receivable']), currency),
      payable: format.money(num(row['payable']), currency),
      net: format.money(Math.abs(net), currency),
      netReceivable: net >= 0,
      cash: cash ? format.money(num(cash['net']), currency) : null,
      opening: opening ? format.money(num(opening['net']), currency) : null,
    };
  });
}

function period(bundle: ExportBundle): string {
  const { from, to } = bundle.header.filters;
  if (!from && !to) return 'Everything to date';
  return `${from ? statementDate(from) : 'The beginning'} — ${to ? statementDate(to) : 'today'}`;
}

function describe(bundle: ExportBundle): string {
  const f = bundle.header.filters;
  const parts: string[] = [];
  if (f.currency) parts.push(`entered in ${f.currency}`);
  if (f.kinds && f.kinds.length > 0) parts.push(f.kinds.join(', '));
  if (f.scope === 'opening') parts.push('opening balances only');
  if (f.scope === 'regular') parts.push('excluding opening balances');
  if (f.include_void) parts.push('including voided history');
  return parts.length === 0 ? 'Every account, every entry' : parts.join(' · ');
}

/** The whole report, ready to draw. */
export function buildWorkspaceReport(
  bundle: ExportBundle,
  format: ReportFormatter,
): WorkspaceReport {
  const { header, entries } = bundle;

  // Sections follow the people list, so the report is ordered the same way the
  // People screen is, and a person with no entries in the period still appears
  // with their balance rather than vanishing from the file.
  const byPerson = new Map<string, ExportEntry[]>();
  for (const entry of entries) {
    const list = byPerson.get(entry.person_id);
    if (list) list.push(entry);
    else byPerson.set(entry.person_id, [entry]);
  }

  const sections: ReportSection[] = header.people.map((person) => {
    const rows = byPerson.get(person.id) ?? [];
    return {
      personId: person.id,
      personName: person.name,
      currency: person.ledger_currency,
      rows: rows.filter((entry) => entry.scope !== 'opening').map((entry) => toRow(entry, format)),
      openingRows: rows
        .filter((entry) => entry.scope === 'opening')
        .map((entry) => toRow(entry, format)),
    };
  });

  return {
    title: 'Accounting export',
    workspaceName:
      text(header.workspace?.business_name) ?? text(header.workspace?.name) ?? 'Accounic',
    ownerName: text(header.workspace?.name),
    exportedAt: header.exported_at,
    period: period(bundle),
    filters: describe(bundle),
    baseCurrency: header.workspace?.base_currency ?? 'INR',
    positions: positions(bundle, format),
    people: header.people.map((person) => personLine(person, format)),
    sections,
    counts: {
      people: header.counts.people,
      entries: header.counts.entries,
      transactions: header.counts.transactions,
      settlements: header.counts.settlements,
    },
    truncated: bundle.truncated,
  };
}
