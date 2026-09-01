/**
 * The shape of `export_workspace()` and `export_entries()` (0025).
 *
 * These mirror the RPC payload exactly and are shared by the CSV, JSON and PDF
 * writers, so a change to the SQL is a type error here rather than a wrong
 * column in a file someone has already saved.
 *
 * Mirrored by `app/lib/data/models/export.dart`.
 */

/** The one schema version every export file carries. */
export const EXPORT_SCHEMA_VERSION = 1;

export interface ExportFilters {
  from: string | null;
  to: string | null;
  person_id: string | null;
  currency: string | null;
  kinds: string[] | null;
  scope: 'all' | 'regular' | 'opening';
  include_void: boolean;
}

export interface ExportCurrency {
  code: string;
  name: string;
  symbol: string;
  /** ISO 4217 minor-unit exponent: what an integer amount in this currency means. */
  decimals: number;
}

export interface ExportWorkspace {
  owner_id: string;
  name: string | null;
  business_name: string | null;
  email: string | null;
  phone: string | null;
  base_currency: string;
  member_since: string | null;
}

export interface ExportPerson {
  id: string;
  name: string;
  type: string | null;
  phone: string | null;
  email: string | null;
  address: string | null;
  notes: string | null;
  is_archived: boolean;
  currency: string | null;
  ledger_currency: string;
  created_at: string;
  /** The `person_balances` row, as the engine states it. */
  balance: Record<string, unknown> | null;
  /** The `person_opening` row, when the account has an opening balance. */
  opening: Record<string, unknown> | null;
}

export interface ExportCounts {
  people: number;
  entries: number;
  transactions: number;
  settlements: number;
  transfers: number;
  opening: number;
  voided: number;
}

/** `export_workspace()` — the header of an export. */
export interface ExportHeader {
  schema_version: number;
  generator: string;
  exported_at: string;
  filters: ExportFilters;
  workspace: ExportWorkspace | null;
  summary: Record<string, unknown> | null;
  currencies: ExportCurrency[];
  people: ExportPerson[];
  counts: ExportCounts;
}

/** One row of the ledger, as `export_entries()` states it. */
export interface ExportEntry {
  id: string;
  kind: 'transaction' | 'settlement';
  type: string | null;
  direction: string | null;
  date: string;
  person_id: string;
  person_name: string | null;
  note: string | null;
  is_void: boolean;
  scope: 'regular' | 'opening';
  opening_role: string | null;
  transfer_id: string | null;
  transfer_role: string | null;
  transfer_counterparty_id: string | null;
  related_transaction_id: string | null;

  /** The figure as it was entered, in the currency it was entered in. */
  entry_amount_minor: number;
  entry_currency: string;
  /** The same money in the account's ledger currency. */
  amount_minor: number;
  ledger_currency: string;
  /** And in the workspace's base currency, when it could be converted. */
  amount_base_minor: number | null;
  base_currency: string;

  exchange_rate_e9: number | null;
  exchange_rate_source: string | null;
  exchange_rate_at: string | null;
  conversion_mode: string | null;

  settled_minor: number | null;
  remaining_minor: number | null;
  settlement_status: string | null;

  created_at: string;
}

/** One page of `export_entries()`. */
export interface ExportEntryPage {
  schema_version: number;
  filters: ExportFilters;
  limit: number;
  offset: number;
  total: number;
  has_more: boolean;
  entries: ExportEntry[];
}

/** A header and every entry it describes: one complete export. */
export interface ExportBundle {
  header: ExportHeader;
  entries: ExportEntry[];
  /** True when the entry list was cut short by the page cap rather than by a filter. */
  truncated: boolean;
}
