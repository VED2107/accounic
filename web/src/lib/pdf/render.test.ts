import { describe, expect, it } from 'vitest';
import { PDFDocument } from 'pdf-lib';
import { buildPersonStatement } from '@/lib/pdf/statement';
import { pdfApprox, pdfMoney } from '@/lib/pdf/money';
import { supportsAll } from '@/lib/pdf/typeface';
import type { Me, PersonOpening, PersonPage, TimelineEntry } from '@/lib/types';

/**
 * The export, actually run (upgrade §47).
 *
 * `statement.test.ts` checks what the statement says. This checks that it can
 * be produced at all: fonts embedded, glyphs present, pages laid out, bytes
 * written. Every one of those failures is a runtime one — a missing glyph makes
 * pdf-lib throw mid-draw, and a layout bug loops forever rather than failing a
 * typecheck — so nothing but running it proves anything.
 *
 * The text inside a PDF is drawn with subsetted glyph ids and cannot be read
 * back without a full text extractor, which is why the *content* assertions
 * live in the other file, against the same row builder this uses.
 */

const AED_INR_E9 = 25_984_225_000;
const USD_INR_E9 = 95_427_612_000;

const me: Me = {
  id: 'o1',
  name: 'Ved Chauhan',
  email: 'owner@example.com',
  phone: null,
  business_name: 'Accounic Test Workspace',
  avatar_url: null,
  currency: 'INR',
  is_active: true,
  is_admin: false,
  created_at: '2026-01-01T00:00:00.000Z',
};

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
  exchange_rate_e9: AED_INR_E9,
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

function entry(index: number, overrides: Partial<TimelineEntry> = {}): TimelineEntry {
  return {
    id: `e${index}`,
    entry_kind: 'transaction',
    entry_type: index % 2 === 0 ? 'credit' : 'debit',
    money_direction: index % 2 === 0 ? 'in' : 'out',
    amount_minor: 100000 + index * 137,
    entry_date: `2026-08-${String((index % 28) + 1).padStart(2, '0')}`,
    note: `Entry number ${index}`,
    is_void: false,
    related_transaction_id: null,
    created_at: `2026-08-${String((index % 28) + 1).padStart(2, '0')}T09:${String(index % 60).padStart(2, '0')}:00.000Z`,
    is_opening: false,
    entered_amount_minor: null,
    entered_currency: null,
    exchange_rate_e9: null,
    exchange_rate_at: null,
    exchange_rate_source: null,
    conversion_mode: null,
    auto_converted_amount_minor: null,
    entry_amount_minor: 100000 + index * 137,
    entry_currency: 'INR',
    ledger_currency: 'INR',
    amount_base_minor: 100000 + index * 137,
    base_currency: 'INR',
    settled_minor: null,
    remaining_minor: null,
    status: null,
    ...overrides,
  };
}

function statementPage(entries: TimelineEntry[]): PersonPage {
  const net = 1039369;
  return {
    person: {
      id: 'p1',
      owner_id: 'o1',
      name: 'Sayan Roy',
      type: 'person',
      phone: '+91 98200 00000',
      email: 'sayan@example.com',
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
      total_credit: 500000,
      total_debit: 200000,
      settled_in: 50000,
      settled_out: 0,
      total_settled: 50000,
      outstanding_receivable: 450000,
      outstanding_payable: 200000,
      net_balance: net,
      net_balance_base: net,
      net_balance_default: net,
      transaction_count: entries.length,
      opening_minor: opening.signed_minor,
      last_activity_at: '2026-08-28',
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
    open_transactions: [],
  };
}

function isPdf(bytes: Uint8Array): boolean {
  return String.fromCharCode(...bytes.slice(0, 5)) === '%PDF-';
}

/**
 * How many pages the document has, by parsing it back.
 *
 * Grepping the bytes for `/Type /Page` does not work and looks as though it
 * should: pdf-lib writes cross-reference and object streams compressed, so the
 * catalogue is not in the file as plain text. Loading it is both correct and a
 * stronger assertion — a document that reparses is a document a reader can
 * open.
 */
async function pageCount(bytes: Uint8Array): Promise<number> {
  const doc = await PDFDocument.load(bytes);
  return doc.getPageCount();
}

describe('the PDF actually renders', () => {
  it('produces a valid single-page PDF for a small account', async () => {
    const bytes = await buildPersonStatement({
      page: statementPage([entry(1), entry(2), entry(3)]),
      me,
      truncated: false,
      rowsCovered: 3,
    });

    expect(isPdf(bytes)).toBe(true);
    // A statement with an embedded subsetted face is a few tens of kB. Anything
    // near zero means the font failed to embed and the text is not there.
    expect(bytes.byteLength).toBeGreaterThan(5000);
    expect(await pageCount(bytes)).toBe(1);
  });

  it('paginates a long account instead of drawing off the bottom of the page', async () => {
    const many = Array.from({ length: 120 }, (_, index) => entry(index + 1));
    const bytes = await buildPersonStatement({
      page: statementPage(many),
      me,
      truncated: true,
      rowsCovered: many.length,
    });

    expect(isPdf(bytes)).toBe(true);
    expect(await pageCount(bytes)).toBeGreaterThan(1);
  });

  it('draws transfers, settlements, voided rows and conversions without throwing', async () => {
    const bytes = await buildPersonStatement({
      page: statementPage([
        entry(1, {
          transfer_id: 't1',
          transfer_role: 'source',
          transfer_counterparty_name: 'Dhruv Sharma',
          entry_type: 'debit',
          money_direction: 'out',
        }),
        entry(2, {
          transfer_id: 't2',
          transfer_role: 'destination',
          transfer_counterparty_name: 'Ved Chauhan',
          entry_type: 'credit',
        }),
        entry(3, { entry_kind: 'settlement', entry_type: 'in', money_direction: 'in' }),
        entry(4, { is_void: true }),
        entry(5, {
          amount_minor: 381711,
          entry_amount_minor: 4000,
          entry_currency: 'USD',
          entered_amount_minor: 4000,
          entered_currency: 'USD',
          exchange_rate_e9: USD_INR_E9,
          exchange_rate_source: 'manual-rate',
        }),
        entry(6, { note: null }),
      ]),
      me,
      truncated: false,
      rowsCovered: 6,
    });

    expect(isPdf(bytes)).toBe(true);
  });

  it('renders an account that has no opening balance and no entries', async () => {
    const empty = statementPage([]);
    const bytes = await buildPersonStatement({
      page: { ...empty, opening: null, balance: { ...empty.balance, opening_minor: 0, net_balance: 0 } },
      me,
      truncated: false,
      rowsCovered: 0,
    });

    expect(isPdf(bytes)).toBe(true);
    expect(await pageCount(bytes)).toBe(1);
  });

  it('survives a name and a note the embedded face cannot draw', async () => {
    // A statement must not fail to generate because somebody's name is in a
    // script Poppins has no glyphs for. Unsupported characters are dropped;
    // nothing throws.
    const page = statementPage([entry(1, { note: 'メモ ☂ ✈' })]);
    const bytes = await buildPersonStatement({
      page: { ...page, person: { ...page.person, name: '田中 太郎' } },
      me,
      truncated: false,
      rowsCovered: 1,
    });

    expect(isPdf(bytes)).toBe(true);
  });
});

describe('the PDF money formatter', () => {
  it('is the app formatter wherever the face can draw the symbol', () => {
    // ₹ and $ are both in Poppins, so a statement prints exactly what the
    // screen prints.
    expect(pdfMoney(1039369, 'INR')).toBe('₹10,393.69 INR');
    expect(pdfMoney(4000, 'USD')).toBe('$40 USD');
    expect(pdfApprox(381711, 'INR')).toBe('≈ ₹3,817.11 INR');
  });

  it('drops only the symbol for a currency the face has no glyph for', () => {
    // ₫ has no glyph in Poppins. The amount, the grouping and the ISO code are
    // untouched; only the mark that could not be drawn is gone.
    expect(supportsAll('₫')).toBe(false);
    const dong = pdfMoney(150000, 'VND');
    expect(dong).toContain('VND');
    expect(dong).not.toContain('₫');
    // The grouping is the currency's own — the dong groups with dots in vi-VN —
    // and the fallback does not touch it. Only the leading mark is gone.
    expect(dong.replace(/\D/g, '')).toBe('150000');
  });

  it('keeps the rupee sign, which is the whole reason a font is embedded', () => {
    // The fourteen built-in PDF fonts are WinAnsi and have no ₹ at all.
    expect(supportsAll('₹')).toBe(true);
    expect(pdfMoney(100000, 'INR')).toContain('₹');
  });
});
