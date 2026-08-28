import { netDelta } from '@/lib/series';
import { entryLabel } from '@/lib/direction';
import { transferLabel } from '@/lib/transfers';
import { normaliseCode } from '@/lib/currencies';
import { statementDate, timeOfDay } from '@/lib/dates';
import type { PersonOpening, PersonPage, TimelineEntry } from '@/lib/types';

/**
 * What a statement says, before anything is drawn (upgrade §47).
 *
 * Split out of `statement.ts` for two reasons, and the second is the important
 * one:
 *
 *   1. it is pure — data in, strings out — so it is testable without a PDF
 *      reader, a font file or a filesystem;
 *   2. it is the ONLY place the statement decides what to say, which is what
 *      makes "the PDF uses the same calculations as the UI" a fact rather than
 *      an intention. Every string below comes from `lib/money.ts` (through the
 *      injected formatter), `lib/direction.ts`, `lib/transfers.ts` or
 *      `lib/dates.ts` — the same four modules the screen uses.
 *
 * The formatter is injected rather than imported because the PDF has one extra
 * constraint the screen does not: the embedded typeface has no glyph for a
 * handful of currency symbols, so `lib/pdf/money.ts` drops those and keeps the
 * ISO code. Injecting it means the row rules can be tested against the plain
 * screen formatter and still be the rules the PDF runs.
 */

export interface StatementFormatter {
  /** `$40.00 USD` — an amount in the currency it was entered in. */
  money(minor: number, currency: string | null | undefined, options?: { compactDecimals?: boolean }): string;
  /** `≈ ₹3,817.11 INR` — the same money converted, marked as a conversion. */
  approx(minor: number, currency: string | null | undefined): string;
  /** `1 USD = ₹95.4276 INR` at the precision that reproduces the figure above. */
  rate(from: string, to: string, rateE9: number, amountMinor?: number | null): string;
}

export interface StatementRow {
  /** `28 Aug 2026` */
  date: string;
  /** `08:42 PM`, or '' when the row carries no usable timestamp. */
  time: string;
  /** `Credit`, `Debit`, `Transfer to Dhruv`, `Settlement received`. */
  type: string;
  description: string;
  /** The amount as entered, in the currency it was entered in. */
  original: string;
  /** The one equivalent worth printing, or null when there is none. */
  equivalent: string | null;
  /** The rate that links the two, or null when nothing was converted. */
  rate: string | null;
  /** The running position after this row, in the account currency. */
  balance: string;
  /** True when the running position is in the user's favour at this row. */
  balanceReceivable: boolean;
  isVoid: boolean;
  isTransfer: boolean;
}

/** What a timeline entry is called — the same three cases the screen uses. */
export function rowType(entry: TimelineEntry): string {
  if (entry.transfer_id) {
    return transferLabel(entry.transfer_role, entry.transfer_counterparty_name);
  }
  if (entry.is_opening) return 'Opening balance';
  return entryLabel(entry.entry_kind, entry.entry_type);
}

/**
 * The other party, or the note.
 *
 * A transfer's counterparty is already named in the type column, so its
 * description carries the note; for everything else the note is all there is.
 */
export function rowDescription(entry: TimelineEntry): string {
  const note = (entry.note ?? '').trim();
  if (note) return note;
  if (entry.transfer_id && entry.transfer_counterparty_name) {
    return entry.transfer_counterparty_name;
  }
  return '—';
}

/**
 * The one equivalent that says something the original figure does not.
 *
 * The ledger figure when the entry was converted INTO this account, otherwise
 * the workspace-currency figure for an account kept in a foreign currency —
 * never both, and never the equivalent on its own. Identical to the rule the
 * person timeline applies, deliberately: a row that showed two figures on
 * screen and three in the export would be two different documents.
 */
export function rowEquivalent(
  row: {
    amount_minor: number;
    entry_currency?: string | null;
    base_currency?: string | null;
    amount_base_minor?: number | null;
  },
  currency: string,
  baseCurrency: string,
): { minor: number; currency: string } | null {
  const entryCurrency = normaliseCode(row.entry_currency) || currency;
  const base = normaliseCode(row.base_currency) || normaliseCode(baseCurrency);

  if (entryCurrency !== currency) return { minor: row.amount_minor, currency };
  if (base && base !== currency && row.amount_base_minor != null) {
    return { minor: row.amount_base_minor, currency: base };
  }
  return null;
}

/** The opening balance, resolved into the four strings a statement prints. */
export interface OpeningLines {
  original: string;
  equivalent: string | null;
  rate: string | null;
  dated: string;
  recorded: string;
  /** Whose favour it runs in, in words. */
  direction: string;
}

export function openingLines(
  opening: PersonOpening,
  openingMinor: number,
  currency: string,
  baseCurrency: string,
  format: StatementFormatter,
): OpeningLines {
  const equivalent = rowEquivalent(
    {
      amount_minor: opening.amount_minor,
      entry_currency: opening.entry_currency,
      base_currency: opening.base_currency,
      amount_base_minor: opening.amount_base_minor,
    },
    currency,
    baseCurrency,
  );

  return {
    // Compact decimals, exactly as the opening-balance card prints it: a whole
    // 400 dirhams reads "400 AED" on screen and must read the same here.
    original: format.money(opening.entry_amount_minor, opening.entry_currency),
    equivalent: equivalent ? format.approx(equivalent.minor, equivalent.currency) : null,
    rate:
      opening.entered_currency && opening.exchange_rate_e9
        ? format.rate(
            opening.entered_currency,
            currency,
            opening.exchange_rate_e9,
            opening.entered_amount_minor,
          )
        : null,
    dated: statementDate(opening.entry_date),
    recorded: `${statementDate(opening.created_at)} at ${timeOfDay(opening.created_at)}`,
    direction:
      openingMinor >= 0
        ? 'Owed to you when the account opened'
        : 'Owed by you when the account opened',
  };
}

/**
 * Every printable row, oldest first, with a running balance.
 *
 * The running balance is walked FORWARD from a figure derived by subtracting
 * every listed entry's effect from the balance the database reports, using
 * `netDelta()` — the same function the person page's sparkline uses. Two
 * consequences worth stating:
 *
 *   * the last row lands exactly on the position printed at the top of the
 *     statement, rather than on an independently accumulated approximation;
 *   * the starting figure already contains the opening balance and anything
 *     older than the rows listed, which is why a truncated export says so.
 */
export function buildStatementRows(
  page: PersonPage,
  currency: string,
  baseCurrency: string,
  format: StatementFormatter,
): StatementRow[] {
  // person_page() returns newest first; a statement reads oldest first.
  const ordered = [...page.timeline].sort((a, b) => {
    if (a.entry_date !== b.entry_date) return a.entry_date < b.entry_date ? -1 : 1;
    return a.created_at < b.created_at ? -1 : 1;
  });

  const total = ordered.reduce((sum, entry) => sum + netDelta(entry), 0);
  let running = page.balance.net_balance - total;

  return ordered.map((entry) => {
    running += netDelta(entry);

    const entryMinor = entry.entry_amount_minor ?? entry.amount_minor;
    const entryCurrency = normaliseCode(entry.entry_currency) || currency;
    const equivalent = rowEquivalent(entry, currency, baseCurrency);

    return {
      date: statementDate(entry.entry_date),
      time: timeOfDay(entry.created_at),
      type: rowType(entry),
      description: rowDescription(entry),
      original: format.money(entryMinor, entryCurrency),
      equivalent: equivalent ? format.approx(equivalent.minor, equivalent.currency) : null,
      rate:
        entry.entered_currency && entry.exchange_rate_e9
          ? format.rate(
              entry.entered_currency,
              currency,
              entry.exchange_rate_e9,
              entry.entered_amount_minor,
            )
          : null,
      balance: format.money(Math.abs(running), currency),
      balanceReceivable: running >= 0,
      isVoid: entry.is_void,
      isTransfer: Boolean(entry.transfer_id),
    };
  });
}
