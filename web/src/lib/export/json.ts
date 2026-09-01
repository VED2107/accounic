import {
  EXPORT_SCHEMA_VERSION,
  type ExportBundle,
  type ExportEntry,
  type ExportPerson,
} from '@/lib/export/types';

/**
 * The workspace export as JSON (milestone 1.9.0, Phase 5).
 *
 * This is the backup format: the one an export exists for. Its obligations are
 * different from the CSV's and stricter:
 *
 *   * VERSIONED. `schema_version` is the first key, so a future reader knows
 *     what it is holding before it parses the rest.
 *   * SELF-DESCRIBING. Every currency used is defined in the file, exponent
 *     included, so an integer amount can be read without knowing Accounic.
 *   * RELATIONAL. People, opening balances, transactions and settlements keep
 *     their ids and their references to each other, so the file could be
 *     imported by a tool that does not exist yet.
 *   * NO SECRETS. It carries the profile's own name, email and phone — the
 *     owner's own data, which is the point of a portability file — and no
 *     token, no key, no password, no session, nothing about any other user.
 *
 * The ledger is split into `opening_balances`, `transactions` and
 * `settlements` rather than shipped as one undifferentiated feed, because the
 * three are different things in this product and flattening them is exactly
 * the mistake the opening-balance work spent a release undoing.
 *
 * Mirrored by `app/lib/core/export_json.dart`.
 */

export interface ExportDocument {
  schema_version: number;
  generator: string;
  exported_at: string;
  filters: unknown;
  truncated: boolean;
  workspace: unknown;
  summary: unknown;
  currencies: unknown;
  people: ExportPerson[];
  opening_balances: ExportEntry[];
  transactions: ExportEntry[];
  settlements: ExportEntry[];
  counts: unknown;
}

export function buildExportDocument(bundle: ExportBundle): ExportDocument {
  const { header, entries, truncated } = bundle;

  const opening = entries.filter((entry) => entry.scope === 'opening');
  const regular = entries.filter((entry) => entry.scope !== 'opening');

  return {
    schema_version: EXPORT_SCHEMA_VERSION,
    generator: header.generator,
    exported_at: header.exported_at,
    filters: header.filters,
    // Stated rather than implied: a file that holds the first 20,000 of 50,000
    // entries must not look like a complete backup.
    truncated,
    workspace: header.workspace,
    summary: header.summary,
    currencies: header.currencies,
    people: header.people,
    opening_balances: opening,
    transactions: regular.filter((entry) => entry.kind === 'transaction'),
    settlements: regular.filter((entry) => entry.kind === 'settlement'),
    counts: header.counts,
  };
}

/** The document as a file's contents. Indented: a backup gets read by people. */
export function exportDocumentToJson(document: ExportDocument): string {
  return `${JSON.stringify(document, null, 2)}\n`;
}

/**
 * The filename an export is offered under.
 *
 * Dated, so a folder of them sorts chronologically, and named after what is in
 * it rather than after the app.
 */
export function exportFilename(
  extension: 'csv' | 'json' | 'pdf',
  options: { scope?: string | null; date?: Date } = {},
): string {
  const date = (options.date ?? new Date()).toISOString().slice(0, 10);
  const slug = (options.scope ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return slug
    ? `accounic-${slug}-${date}.${extension}`
    : `accounic-export-${date}.${extension}`;
}
