import { describe, expect, it } from 'vitest';
import { buildStatementRows, openingLines, type StatementFormatter } from '@/lib/pdf/rows';
import { formatApprox, formatMoney } from '@/lib/money';
import { rateSentence } from '@/lib/currencies';
import type { PersonOpening, PersonPage, TimelineEntry } from '@/lib/types';

/**
 * The statement, checked against what it is supposed to contain (upgrade §47).
 *
 * The formatter here is the SCREEN's — `lib/money.ts` directly, with no PDF
 * glyph fallback — and that is the point of the test rather than a shortcut:
 * `lib/pdf/rows.ts` is the only place the export decides what to say, so
 * running it with the screen's formatter proves the export and the screen
 * produce the same strings from the same data.
 */
const FORMAT: StatementFormatter = {
  money: (minor, currency, options) => formatMoney(minor, currency, options),
  approx: (minor, currency) => formatApprox(minor, currency),
  rate: (from, to, rateE9, amountMinor) => rateSentence(from, to, rateE9, amountMinor),
};

const USD_INR_E9 = 95_427_612_000;

function entry(overrides: Partial<TimelineEntry>): TimelineEntry {
  return {
    id: overrides.id ?? crypto.randomUUID(),
    entry_kind: 'transaction',
    entry_type: 'credit',
    money_direction: 'in',
    amount_minor: 100000,
    entry_date: '2026-08-28',
    note: null,
    is_void: false,
    related_transaction_id: null,
    created_at: '2026-08-28T15:12:00.000Z',
    is_opening: false,
    entered_amount_minor: null,
    entered_currency: null,
    exchange_rate_e9: null,
    exchange_rate_at: null,
    exchange_rate_source: null,
    conversion_mode: null,
    auto_converted_amount_minor: null,
    settled_minor: null,
    remaining_minor: null,
    status: null,
    ...overrides,
  };
}

function page(entries: TimelineEntry[], net: number, opening: PersonOpening | null = null): PersonPage {
  return {
    person: {
      id: 'p1',
      owner_id: 'o1',
      name: 'Sayan Roy',
      type: 'person',
      phone: null,
      email: null,
      address: null,
      notes: null,
      currency: 'INR',
      ledger_currency: null,
      is_archived: false,
      created_at: '2026-01-01T00:00:00.000Z',
      updated_at: '2026-01-01T00:00:00.000Z',
    },
    balance: {
      person_id: 'p1',
      owner_id: 'o1',
      name: 'Sayan Roy',
      type: 'person',
      phone: null,
      email: null,
      is_archived: false,
      currency: 'INR',
      default_currency: 'INR',
      base_currency: 'INR',
      total_credit: 0,
      total_debit: 0,
      settled_in: 0,
      settled_out: 0,
      total_settled: 0,
      outstanding_receivable: 0,
      outstanding_payable: 0,
      net_balance: net,
      net_balance_base: net,
      net_balance_default: net,
      transaction_count: entries.length,
      opening_minor: opening?.signed_minor ?? 0,
      last_activity_at: null,
      // db/migrations/0022: the two halves of net_balance. These fixtures
      // have no opening balance unless one is passed, so cash in hand is the
      // whole position and the opening half is zero — which is exactly what
      // the invariant demands.
      cash_in_hand_minor: net - (opening?.signed_minor ?? 0),
      cash_in_hand_base: net - (opening?.signed_minor ?? 0),
      opening_net_minor: opening?.signed_minor ?? 0,
      opening_net_base: opening?.signed_minor ?? 0,
      regular_credit_minor: 0,
      regular_debit_minor: 0,
      regular_receivable: 0,
      regular_payable: 0,
      regular_settled_total: 0,
      opening_credit_minor: 0,
      opening_debit_minor: 0,
      opening_receivable: 0,
      opening_payable: 0,
      opening_settled_total: 0,
      opening_entry_count: opening ? 1 : 0,
    },
    currency: 'INR',
    default_currency: 'INR',
    base_currency: 'INR',
    opening,
    opening_history: [],
    opening_activity: [],
    regular: {
      currency: 'INR',
      base_currency: 'INR',
      position: net - (opening?.signed_minor ?? 0),
      position_base: net - (opening?.signed_minor ?? 0),
      receivable: 0,
      payable: 0,
      settled: 0,
      credit: 0,
      debit: 0,
    },
    opening_position: {
      currency: 'INR',
      base_currency: 'INR',
      position: opening?.signed_minor ?? 0,
      position_base: opening?.signed_minor ?? 0,
      receivable: 0,
      payable: 0,
      settled: 0,
      credit: 0,
      debit: 0,
      entry_count: opening ? 1 : 0,
    },
    timeline: entries,
    timeline_total: entries.length,
    regular_by_currency: [],
    opening_by_currency: [],
    open_transactions: [],
  };
}

/**
 * `buildStatementRows` for a whole page.
 *
 * Since db/migrations/0022 the function takes the rows and the position they
 * close on, so the same code can walk the regular timeline and the opening
 * book. These tests are all about the regular timeline, so this names that
 * pairing once instead of at every call site.
 */
function buildStatementRowsFor(
  data: PersonPage,
  currency: string,
  baseCurrency: string,
  format: StatementFormatter,
) {
  return buildStatementRows(data.timeline, data.regular.position, currency, baseCurrency, format);
}

describe('what a statement row says', () => {
  it('carries the date, the time, the type, the original amount and its currency', () => {
    const rows = buildStatementRowsFor(
      page(
        [
          entry({
            entry_type: 'credit',
            amount_minor: 381711,
            entry_amount_minor: 4000,
            entry_currency: 'USD',
            entered_amount_minor: 4000,
            entered_currency: 'USD',
            exchange_rate_e9: USD_INR_E9,
            note: 'Sayan',
          }),
        ],
        381711,
      ),
      'INR',
      'INR',
      FORMAT,
    );

    const [row] = rows;
    expect(row).toBeDefined();
    // 28 Aug 2026 | 08:42 PM | Debit | $40.00 USD | ≈ ₹3,817.11 INR | Sayan
    expect(row!.date).toBe('28 Aug 2026');
    expect(row!.time).toMatch(/^\d{2}:\d{2} (AM|PM)$/);
    // The stored enum reads backwards on purpose — see lib/direction.ts. What
    // matters is that the export uses the SAME mapping the screen does.
    expect(row!.type).toBe('Debit');
    // Compact on a whole amount, exactly as every screen prints it.
    expect(row!.original).toBe('$40 USD');
    expect(row!.equivalent).toBe('≈ ₹3,817.11 INR');
    expect(row!.description).toBe('Sayan');
  });

  it('prints the rate at a precision that reproduces the converted figure', () => {
    const rows = buildStatementRowsFor(
      page(
        [
          entry({
            amount_minor: 381710,
            entry_amount_minor: 4000,
            entry_currency: 'USD',
            entered_amount_minor: 4000,
            entered_currency: 'USD',
            exchange_rate_e9: USD_INR_E9,
          }),
        ],
        381710,
      ),
      'INR',
      'INR',
      FORMAT,
    );

    expect(rows[0]!.rate).toContain('1 USD = ');
    expect(rows[0]!.rate).toContain('INR');
  });

  it('never shows an INR equivalent as if it were the original amount', () => {
    const rows = buildStatementRowsFor(
      page(
        [
          entry({
            amount_minor: 381711,
            entry_amount_minor: 4000,
            entry_currency: 'USD',
          }),
        ],
        381711,
      ),
      'INR',
      'INR',
      FORMAT,
    );
    // The leading figure is the dollars the user typed, and the rupee figure is
    // explicitly marked as a conversion.
    expect(rows[0]!.original.startsWith('$40')).toBe(true);
    expect(rows[0]!.equivalent!.startsWith('≈')).toBe(true);
  });

  it('shows no equivalent when nothing was converted', () => {
    const rows = buildStatementRowsFor(
      page([entry({ amount_minor: 100000, entry_amount_minor: 100000, entry_currency: 'INR' })], 100000),
      'INR',
      'INR',
      FORMAT,
    );
    expect(rows[0]!.original).toBe('₹1,000 INR');
    expect(rows[0]!.equivalent).toBeNull();
    expect(rows[0]!.rate).toBeNull();
  });
});

describe('transfers on a statement', () => {
  it('names the other party rather than calling the leg a credit or a debit', () => {
    const rows = buildStatementRowsFor(
      page(
        [
          entry({
            id: 'src',
            entry_type: 'debit',
            money_direction: 'out',
            amount_minor: 300000,
            entry_amount_minor: 300000,
            entry_currency: 'INR',
            transfer_id: 't1',
            transfer_role: 'source',
            transfer_counterparty_name: 'Dhruv',
          }),
        ],
        700000,
      ),
      'INR',
      'INR',
      FORMAT,
    );

    expect(rows[0]!.type).toBe('Transfer to Dhruv');
    expect(rows[0]!.isTransfer).toBe(true);
    expect(rows[0]!.original).toBe('₹3,000 INR');
  });

  it('reads from the other side too', () => {
    const rows = buildStatementRowsFor(
      page(
        [
          entry({
            id: 'dst',
            entry_type: 'credit',
            amount_minor: 300000,
            entry_amount_minor: 300000,
            entry_currency: 'INR',
            transfer_id: 't1',
            transfer_role: 'destination',
            transfer_counterparty_name: 'Ved',
          }),
        ],
        500000,
      ),
      'INR',
      'INR',
      FORMAT,
    );
    expect(rows[0]!.type).toBe('Transfer from Ved');
  });
});

describe('the running balance', () => {
  it('lands exactly on the position the database reports', () => {
    const rows = buildStatementRowsFor(
      page(
        [
          entry({ id: 'a', entry_type: 'credit', amount_minor: 500000, entry_date: '2026-08-01' }),
          entry({ id: 'b', entry_type: 'debit', amount_minor: 200000, entry_date: '2026-08-10' }),
          entry({ id: 'c', entry_type: 'credit', amount_minor: 100000, entry_date: '2026-08-20' }),
        ],
        400000,
      ),
      'INR',
      'INR',
      FORMAT,
    );

    // Oldest first, and the last row is the reported net position.
    expect(rows).toHaveLength(3);
    expect(rows[0]!.date).toBe('01 Aug 2026');
    expect(rows.at(-1)!.balance).toBe('₹4,000 INR');
  });

  it('ignores voided entries, exactly as every balance does', () => {
    const rows = buildStatementRowsFor(
      page(
        [
          entry({ id: 'a', entry_type: 'credit', amount_minor: 500000, entry_date: '2026-08-01' }),
          entry({
            id: 'b',
            entry_type: 'credit',
            amount_minor: 900000,
            entry_date: '2026-08-05',
            is_void: true,
          }),
        ],
        500000,
      ),
      'INR',
      'INR',
      FORMAT,
    );

    expect(rows[1]!.isVoid).toBe(true);
    // The voided row moves nothing, so the balance is unchanged across it.
    expect(rows[0]!.balance).toBe(rows[1]!.balance);
  });
});

describe('the opening balance block', () => {
  const opening: PersonOpening = {
    person_id: 'p1',
    owner_id: 'o1',
    transaction_id: 'op1',
    entry_type: 'credit',
    signed_minor: 1039369,
    amount_minor: 1039369,
    ledger_currency: 'INR',
    entry_amount_minor: 40000,
    entry_currency: 'AED',
    amount_base_minor: 1039369,
    base_currency: 'INR',
    entered_amount_minor: 40000,
    entered_currency: 'AED',
    exchange_rate_e9: 25_984_225_000,
    exchange_rate_at: '2026-08-20T10:00:00.000Z',
    exchange_rate_source: 'open.er-api.com',
    rate_is_manual: false,
    conversion_mode: 'automatic',
    auto_converted_amount_minor: null,
    entry_date: '2026-08-20',
    note: 'Opening balance',
    created_at: '2026-08-20T10:00:00.000Z',
    settled_minor: 0,
    remaining_minor: 1039369,
    status: 'open',
  };

  it('leads with the original amount and its currency, not the conversion', () => {
    const lines = openingLines(opening, 1039369, 'INR', 'INR', FORMAT);
    // 400 AED, and ≈ ₹10,393.69 INR under it — the example from the brief.
    expect(lines.original).toBe('400 AED');
    expect(lines.equivalent).toBe('≈ ₹10,393.69 INR');
    expect(lines.rate).toContain('1 AED = ');
    expect(lines.dated).toBe('20 Aug 2026');
    expect(lines.recorded).toMatch(/^20 Aug 2026 at \d{2}:\d{2} (AM|PM)$/);
    expect(lines.direction).toContain('Owed to you');
  });

  it('is never one of the transaction rows', () => {
    const built = page([entry({ id: 'x', amount_minor: 100000 })], 1139369, opening);
    const rows = buildStatementRowsFor(built, 'INR', 'INR', FORMAT);
    expect(rows.every((row) => row.type !== 'Opening balance')).toBe(true);
    expect(rows).toHaveLength(1);
  });

  it('says which way it runs when the user is the one who owes', () => {
    const lines = openingLines({ ...opening, signed_minor: -1039369 }, -1039369, 'INR', 'INR', FORMAT);
    expect(lines.direction).toContain('Owed by you');
  });
});
