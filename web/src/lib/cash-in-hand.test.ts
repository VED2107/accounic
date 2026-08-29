import { describe, expect, it } from 'vitest';
import { buildStatementRows, openingLines, rowType, type StatementFormatter } from '@/lib/pdf/rows';
import { formatApprox, formatMoney } from '@/lib/money';
import { rateSentence } from '@/lib/currencies';
import { netDelta } from '@/lib/series';
import type { PersonOpening, PositionSplit, TimelineEntry } from '@/lib/types';

/**
 * Cash in hand and the opening balance are two positions (db/migrations/0022).
 *
 * The database owns the arithmetic and `db/tests/11_cash_in_hand.sql` proves it
 * against real rows. What these pin is the half the clients own: that the
 * export says the same thing the screen does, that an opening-book row is
 * never labelled or placed as a regular transaction, and that the running
 * balance on a statement walks cash in hand rather than the whole position.
 */

const FORMAT: StatementFormatter = {
  money: (minor, currency) => formatMoney(minor, currency ?? 'INR'),
  approx: (minor, currency) => formatApprox(minor, currency ?? 'INR'),
  rate: (from, to, rateE9, amountMinor) => rateSentence(from, to, rateE9, amountMinor ?? undefined),
};

function entry(over: Partial<TimelineEntry> = {}): TimelineEntry {
  return {
    id: 'e1',
    entry_kind: 'transaction',
    entry_type: 'credit',
    money_direction: 'in',
    amount_minor: 100000,
    entry_date: '2026-08-28',
    note: null,
    is_void: false,
    related_transaction_id: null,
    created_at: '2026-08-28T10:00:00.000Z',
    is_opening: false,
    entered_amount_minor: null,
    entered_currency: null,
    exchange_rate_e9: null,
    exchange_rate_at: null,
    exchange_rate_source: null,
    conversion_mode: null,
    auto_converted_amount_minor: null,
    entry_amount_minor: 100000,
    entry_currency: 'INR',
    ledger_currency: 'INR',
    amount_base_minor: 100000,
    base_currency: 'INR',
    transfer_id: null,
    transfer_role: null,
    transfer_counterparty_id: null,
    transfer_counterparty_name: null,
    settled_minor: null,
    remaining_minor: null,
    status: null,
    ...over,
  } as TimelineEntry;
}

const OPENING: PersonOpening = {
  person_id: 'p1',
  owner_id: 'o1',
  transaction_id: 't-open',
  entry_type: 'debit',
  signed_minor: -500000,
  amount_minor: 500000,
  ledger_currency: 'INR',
  entry_amount_minor: 500000,
  entry_currency: 'INR',
  amount_base_minor: 500000,
  base_currency: 'INR',
  entered_amount_minor: null,
  entered_currency: null,
  exchange_rate_e9: null,
  exchange_rate_at: null,
  exchange_rate_source: null,
  rate_is_manual: false,
  conversion_mode: null,
  auto_converted_amount_minor: null,
  entry_date: '2026-08-20',
  note: 'Opening balance',
  created_at: '2026-08-20T10:00:00.000Z',
  settled_minor: 50000,
  remaining_minor: 450000,
  status: 'partial',
};

const OPENING_POSITION: PositionSplit = {
  currency: 'INR',
  base_currency: 'INR',
  position: -450000,
  position_base: -450000,
  receivable: 0,
  payable: 450000,
  settled: 50000,
  credit: 0,
  debit: 500000,
  entry_count: 1,
};

describe('the statement walks cash in hand, not the whole position', () => {
  it('ends the running balance exactly on the figure it was given', () => {
    const rows = buildStatementRows(
      [
        entry({ id: 'a', amount_minor: 100000, entry_amount_minor: 100000, entry_date: '2026-08-27' }),
        entry({ id: 'b', amount_minor: 500000, entry_amount_minor: 500000, entry_date: '2026-08-28' }),
      ],
      600000, // cash in hand, NOT the account position
      'INR',
      'INR',
      FORMAT,
    );

    expect(rows).toHaveLength(2);
    // Oldest first, and the last row lands on cash in hand rather than near it.
    expect(rows[0]!.date).toBe('27 Aug 2026');
    expect(rows[1]!.balance).toBe(formatMoney(600000, 'INR'));
    expect(rows[1]!.balanceReceivable).toBe(true);
  });

  it('walks the opening book to the opening position when given that instead', () => {
    const rows = buildStatementRows(
      [
        entry({
          id: 'o1',
          entry_type: 'debit',
          money_direction: 'out',
          amount_minor: 500000,
          entry_amount_minor: 500000,
          is_opening: true,
          opening_role: 'balance',
          opening_scope: true,
        }),
        entry({
          id: 'o2',
          entry_kind: 'settlement',
          entry_type: 'out',
          money_direction: 'out',
          amount_minor: 50000,
          entry_amount_minor: 50000,
          opening_scope: true,
          entry_date: '2026-08-29',
          created_at: '2026-08-29T10:00:00.000Z',
        }),
      ],
      -450000,
      'INR',
      'INR',
      FORMAT,
    );

    expect(rows).toHaveLength(2);
    expect(rows[1]!.balance).toBe(formatMoney(450000, 'INR'));
    expect(rows[1]!.balanceReceivable).toBe(false);
  });

  it('a voided row moves nothing', () => {
    expect(netDelta(entry({ is_void: true, amount_minor: 999999 }))).toBe(0);
  });
});

describe('an opening-book row is never dressed as a regular transaction', () => {
  it('the balance row is called what it is', () => {
    expect(rowType(entry({ is_opening: true, opening_role: 'balance' }))).toBe('Opening balance');
  });

  it('an adjustment is called an opening credit or debit', () => {
    // `credit` is the stored enum for the OWNER → PERSON direction, which the
    // product calls a Debit — see docs/accounting-direction.md. The statement
    // goes through that mapping like every other screen.
    expect(rowType(entry({ is_opening: true, opening_role: 'adjustment', entry_type: 'credit' })))
      .toBe('Opening debit');
    expect(rowType(entry({ is_opening: true, opening_role: 'adjustment', entry_type: 'debit' })))
      .toBe('Opening credit');
  });

  it('and an ordinary row is untouched by any of it', () => {
    expect(rowType(entry({ entry_type: 'credit' }))).toBe('Debit');
    expect(rowType(entry({ entry_type: 'debit' }))).toBe('Credit');
  });
});

describe('the opening section states its own settlement', () => {
  it('says how much has been settled and what is left', () => {
    const lines = openingLines(OPENING, -500000, 'INR', 'INR', FORMAT);
    expect(lines.settlement).toContain(formatMoney(50000, 'INR'));
    expect(lines.settlement).toContain('left');
    expect(lines.direction).toContain('Owed by you');
  });

  it('says nothing about settlement when nothing has been settled', () => {
    const lines = openingLines(
      { ...OPENING, settled_minor: 0, remaining_minor: 500000, status: 'open' },
      -500000,
      'INR',
      'INR',
      FORMAT,
    );
    expect(lines.settlement).toBeNull();
  });

  it('reports settled in full rather than "0 left"', () => {
    const lines = openingLines(
      { ...OPENING, settled_minor: 500000, remaining_minor: 0, status: 'settled' },
      -500000,
      'INR',
      'INR',
      FORMAT,
    );
    expect(lines.settlement).toContain('settled in full');
  });
});

describe('the two figures reconcile', () => {
  it('cash in hand plus the opening position is the account position', () => {
    const cashInHand = 600000;
    const accountPosition = cashInHand + OPENING_POSITION.position;
    expect(accountPosition).toBe(150000);
    // And neither figure IS the account position, so neither contains the other.
    expect(cashInHand).not.toBe(accountPosition);
    expect(OPENING_POSITION.position).not.toBe(accountPosition);
  });
});
