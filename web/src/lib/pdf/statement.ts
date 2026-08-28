import 'server-only';

import { PDFDocument, StandardFonts, rgb, type PDFFont, type PDFPage } from 'pdf-lib';
import fontkit from '@pdf-lib/fontkit';

import { loadTypeface, drawable } from '@/lib/pdf/typeface';
import { pdfApprox, pdfMoney, pdfRate } from '@/lib/pdf/money';
import {
  buildStatementRows,
  openingLines,
  type StatementFormatter,
  type StatementRow,
} from '@/lib/pdf/rows';
import { balanceTone } from '@/lib/money';
import { currencyLabel } from '@/lib/currencies';
import { statementDate, timeOfDay } from '@/lib/dates';
import type { Me, PersonPage } from '@/lib/types';

/**
 * The PDF's formatter: `lib/money.ts` throughout, with the one adjustment the
 * page medium forces — a currency symbol the embedded face cannot draw is
 * dropped in favour of the ISO code it already carries.
 */
const FORMAT: StatementFormatter = {
  money: pdfMoney,
  approx: pdfApprox,
  rate: pdfRate,
};

/**
 * The account statement, as a PDF (upgrade §47).
 *
 * ONE RULE GOVERNS THIS FILE: it computes no money.
 *
 * Every figure printed below is either a number the database returned or a
 * string `lib/money.ts` produced from one. The running balance is walked with
 * `netDelta()` — the same function the person page's sparkline uses — rather
 * than with arithmetic invented here, the labels come from `lib/direction.ts`
 * and `lib/transfers.ts`, and the dates from `lib/dates.ts`. A statement that
 * disagreed with the screen it was exported from would be worse than no
 * statement at all, and the only way to guarantee it cannot is to give it
 * nothing of its own to disagree with.
 *
 * The structure mirrors the screen exactly, and for the same reason:
 *
 *     Opening balance        its own block, never a row in the table
 *     Regular transactions   credits, debits, transfers, settlements
 *
 * Layout is hand-set rather than templated. pdf-lib draws text at coordinates
 * and measures strings; there is no flow engine, so column positions, row
 * heights and page breaks are computed here and nowhere else.
 */

/* -------------------------------------------------------------------------- */
/* Page geometry                                                               */
/* -------------------------------------------------------------------------- */

const PAGE_WIDTH = 595.28; // A4 portrait, points
const PAGE_HEIGHT = 841.89;
const MARGIN = 36;
const CONTENT_WIDTH = PAGE_WIDTH - MARGIN * 2; // 523.28

/**
 * Column x-offsets from the left margin, and their widths. They sum to
 * CONTENT_WIDTH with a 4pt gutter between each.
 *
 * Sized against the longest real content rather than by eye, which is how the
 * first attempt went wrong: `Transfer to Dhruv Sharma` is the widest type a
 * transfer produces, and a five-figure rupee balance with its ISO code is the
 * widest thing the last column ever holds. Both were being ellipsised, and an
 * ellipsised balance on a statement is worse than an ugly one.
 */
const COLUMNS = {
  date: { x: 0, width: 74 },
  // Wide enough for `Transfer to Dhruv Sharma`, which is the longest label the
  // type column can hold and was still being ellipsised at 106.
  type: { x: 78, width: 118 },
  description: { x: 200, width: 74 },
  original: { x: 278, width: 70 },
  equivalent: { x: 352, width: 80 },
  balance: { x: 436, width: 87 },
} as const;

/**
 * Who publishes this document.
 *
 * Deliberately only what is actually known: the product, the company that makes
 * it, and the repository the release comes from. No address, no registration
 * number and no contact line — a statement is a financial document, and
 * inventing corporate particulars on one would be worse than omitting them.
 * Add real ones here when there are real ones to add.
 */
const PUBLISHER = 'SnowBros';
const PRODUCT_HOME = 'github.com/VED2107/accounic';

const INK = rgb(0.09, 0.11, 0.15);
const INK_MUTED = rgb(0.38, 0.42, 0.49);
const INK_FAINT = rgb(0.56, 0.6, 0.66);
const LINE = rgb(0.87, 0.89, 0.92);
const SUNKEN = rgb(0.968, 0.973, 0.98);
const BRAND = rgb(0.145, 0.388, 0.922); // --brand-2 #2563eb
const RECEIVABLE = rgb(0.086, 0.639, 0.29);
const PAYABLE = rgb(0.86, 0.15, 0.15);

/* -------------------------------------------------------------------------- */
/* Drawing helpers                                                             */
/* -------------------------------------------------------------------------- */

interface Ctx {
  doc: PDFDocument;
  page: PDFPage;
  regular: PDFFont;
  bold: PDFFont;
  /** Distance from the top of the page to the next thing drawn. */
  y: number;
  pageNumber: number;
}

/** `text` shortened until it fits `width`, with an ellipsis when it was cut. */
function fit(text: string, font: PDFFont, size: number, width: number): string {
  const safe = drawable(text);
  if (font.widthOfTextAtSize(safe, size) <= width) return safe;

  let cut = safe;
  while (cut.length > 1 && font.widthOfTextAtSize(`${cut}…`, size) > width) {
    cut = cut.slice(0, -1);
  }
  return `${cut}…`;
}

function drawRight(
  ctx: Ctx,
  text: string,
  right: number,
  y: number,
  font: PDFFont,
  size: number,
  color = INK,
) {
  const safe = drawable(text);
  const width = font.widthOfTextAtSize(safe, size);
  ctx.page.drawText(safe, { x: right - width, y, size, font, color });
}

function drawLeft(
  ctx: Ctx,
  text: string,
  x: number,
  y: number,
  font: PDFFont,
  size: number,
  color = INK,
) {
  ctx.page.drawText(drawable(text), { x, y, size, font, color });
}

/**
 * `Label   value`, both right-aligned against the right margin.
 *
 * The label sits immediately left of its value, measured, so a long value
 * pushes the label along instead of being written over by it.
 */
function labelledRight(ctx: Ctx, label: string, value: string, y: number) {
  const valueWidth = ctx.regular.widthOfTextAtSize(drawable(value), 9);
  drawRight(ctx, value, PAGE_WIDTH - MARGIN, y, ctx.regular, 9);
  drawRight(ctx, label, PAGE_WIDTH - MARGIN - valueWidth - 10, y, ctx.regular, 8, INK_MUTED);
}

function rule(ctx: Ctx, y: number, color = LINE) {
  ctx.page.drawLine({
    start: { x: MARGIN, y },
    end: { x: PAGE_WIDTH - MARGIN, y },
    thickness: 0.5,
    color,
  });
}

/* -------------------------------------------------------------------------- */
/* The statement                                                               */
/* -------------------------------------------------------------------------- */

export interface StatementInput {
  page: PersonPage;
  me: Me | null;
  /** True when the account has more history than the export could fetch. */
  truncated: boolean;
  /** How many entries the statement actually covers. */
  rowsCovered: number;
}

export async function buildPersonStatement(input: StatementInput): Promise<Uint8Array> {
  const { page: data, me, truncated } = input;

  const currency = data.currency ?? me?.currency ?? 'INR';
  const baseCurrency = data.base_currency ?? me?.currency ?? 'INR';
  const person = data.person;
  const balance = data.balance;
  const opening = data.opening ?? null;

  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);

  const typeface = loadTypeface();
  // Subsetted, so a statement carries the few hundred glyphs it uses rather
  // than the whole face — roughly 20 kB instead of 300.
  const regular = await doc.embedFont(typeface.regular, { subset: true });
  const bold = await doc.embedFont(typeface.bold, { subset: true });
  // Never drawn from. Registered so that a font failure surfaces here, at
  // build time, rather than halfway down page three.
  await doc.embedStandardFont(StandardFonts.Helvetica);

  doc.setTitle(`${person.name} — account statement`);
  doc.setAuthor(me?.business_name || me?.name || 'Accounic');
  doc.setCreator('Accounic');
  doc.setProducer('Accounic');
  doc.setCreationDate(new Date());

  const ctx: Ctx = {
    doc,
    page: doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]),
    regular,
    bold,
    y: PAGE_HEIGHT - MARGIN,
    pageNumber: 1,
  };

  drawMasthead(ctx);
  drawIdentity(ctx, person.name, person.type, person.phone, person.email, person.is_archived);
  drawPosition(ctx, balance.net_balance, currency, balance.net_balance_base, baseCurrency, person.name);
  drawOpening(ctx, opening, balance.opening_minor, currency, baseCurrency);

  const rows = buildStatementRows(data, currency, baseCurrency, FORMAT);
  drawTable(ctx, rows, currency, baseCurrency, truncated);
  drawTotals(ctx, data, currency);
  paginate(ctx, person.name);

  return doc.save();
}

function newPage(ctx: Ctx) {
  ctx.page = ctx.doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  ctx.pageNumber += 1;
  ctx.y = PAGE_HEIGHT - MARGIN;
}

/** Reserve `needed` points; start a new page when the current one is full. */
function ensure(ctx: Ctx, needed: number) {
  if (ctx.y - needed < MARGIN + 44) newPage(ctx);
}

function drawMasthead(ctx: Ctx) {
  ctx.y -= 14;
  drawLeft(ctx, 'Accounic', MARGIN, ctx.y, ctx.bold, 15, BRAND);
  drawRight(ctx, 'Account statement', PAGE_WIDTH - MARGIN, ctx.y, ctx.bold, 10.5, INK_MUTED);

  ctx.y -= 13;
  // No workspace or business name under the wordmark. The statement is about
  // the account it names, and the owner is the person exporting it — printing
  // their trading name on every page told them something they already knew and
  // put it on a document they may be handing to somebody else.
  drawRight(
    ctx,
    `Generated ${statementDate(new Date().toISOString())} at ${timeOfDay(new Date().toISOString())}`,
    PAGE_WIDTH - MARGIN,
    ctx.y,
    ctx.regular,
    8.5,
    INK_FAINT,
  );

  ctx.y -= 10;
  rule(ctx, ctx.y);
  ctx.y -= 22;
}

function drawIdentity(
  ctx: Ctx,
  name: string,
  type: string,
  phone: string | null,
  email: string | null,
  archived: boolean,
) {
  drawLeft(ctx, fit(name, ctx.bold, 19, CONTENT_WIDTH), MARGIN, ctx.y, ctx.bold, 19);
  ctx.y -= 13;

  const detail = [
    type.charAt(0).toUpperCase() + type.slice(1),
    phone ?? '',
    email ?? '',
    archived ? 'Archived' : '',
  ]
    .filter(Boolean)
    .join('  ·  ');
  drawLeft(ctx, fit(detail, ctx.regular, 9, CONTENT_WIDTH), MARGIN, ctx.y, ctx.regular, 9, INK_MUTED);
  ctx.y -= 20;
}

function drawPosition(
  ctx: Ctx,
  netMinor: number,
  currency: string,
  netBaseMinor: number | null,
  baseCurrency: string,
  name: string,
) {
  const tone = balanceTone(netMinor);
  const height = currency !== baseCurrency && netBaseMinor !== null ? 74 : 62;

  ctx.page.drawRectangle({
    x: MARGIN,
    y: ctx.y - height,
    width: CONTENT_WIDTH,
    height,
    color: SUNKEN,
    borderColor: LINE,
    borderWidth: 0.5,
  });

  const firstName = name.split(' ')[0] ?? name;
  let y = ctx.y - 17;
  drawLeft(ctx, 'Current position', MARGIN + 14, y, ctx.regular, 8.5, INK_MUTED);

  y -= 22;
  drawLeft(
    ctx,
    pdfMoney(Math.abs(netMinor), currency, { compactDecimals: false }),
    MARGIN + 14,
    y,
    ctx.bold,
    19,
    tone === 'receivable' ? RECEIVABLE : tone === 'payable' ? PAYABLE : INK,
  );

  y -= 13;
  drawLeft(
    ctx,
    tone === 'receivable'
      ? `${firstName} owes you`
      : tone === 'payable'
        ? `You owe ${firstName}`
        : 'Everything is settled',
    MARGIN + 14,
    y,
    ctx.regular,
    8.5,
    tone === 'receivable' ? RECEIVABLE : tone === 'payable' ? PAYABLE : INK_MUTED,
  );

  if (currency !== baseCurrency && netBaseMinor !== null) {
    y -= 12;
    drawLeft(
      ctx,
      `${pdfApprox(Math.abs(netBaseMinor), baseCurrency)} at today’s rate`,
      MARGIN + 14,
      y,
      ctx.regular,
      8.5,
      INK_FAINT,
    );
  }

  // The two denominations in play, on the right of the same box.
  drawRight(ctx, 'Account currency', PAGE_WIDTH - MARGIN - 14, ctx.y - 17, ctx.regular, 8.5, INK_MUTED);
  drawRight(
    ctx,
    fit(currencyLabel(currency), ctx.bold, 9.5, 240),
    PAGE_WIDTH - MARGIN - 14,
    ctx.y - 31,
    ctx.bold,
    9.5,
  );
  drawRight(ctx, 'Workspace currency', PAGE_WIDTH - MARGIN - 14, ctx.y - 46, ctx.regular, 8.5, INK_MUTED);
  drawRight(
    ctx,
    fit(currencyLabel(baseCurrency), ctx.regular, 9.5, 240),
    PAGE_WIDTH - MARGIN - 14,
    ctx.y - 58,
    ctx.regular,
    9.5,
    INK_MUTED,
  );

  ctx.y -= height + 22;
}

/**
 * The opening balance, above the table and outside it.
 *
 * This is the whole point of the section split: a reader must be able to see
 * what the account was carried in with without hunting for it among thirty
 * ordinary entries, and must not mistake it for one.
 */
function drawOpening(
  ctx: Ctx,
  opening: PersonPage['opening'],
  openingMinor: number,
  currency: string,
  baseCurrency: string,
) {
  ensure(ctx, 92);
  drawLeft(ctx, 'OPENING BALANCE', MARGIN, ctx.y, ctx.bold, 8, INK_FAINT);
  ctx.y -= 6;
  rule(ctx, ctx.y);
  ctx.y -= 16;

  if (!opening) {
    drawLeft(
      ctx,
      'No opening balance. This account started at zero.',
      MARGIN,
      ctx.y,
      ctx.regular,
      9,
      INK_MUTED,
    );
    ctx.y -= 24;
    return;
  }

  const lines = openingLines(opening, openingMinor, currency, baseCurrency, FORMAT);

  // The original figure leads, in the currency it was stated in.
  drawLeft(
    ctx,
    lines.original,
    MARGIN,
    ctx.y,
    ctx.bold,
    14,
    openingMinor > 0 ? RECEIVABLE : openingMinor < 0 ? PAYABLE : INK,
  );

  if (lines.equivalent) {
    ctx.y -= 13;
    drawLeft(ctx, lines.equivalent, MARGIN, ctx.y, ctx.regular, 9.5, INK_FAINT);
  }

  ctx.y -= 13;
  drawLeft(ctx, lines.direction, MARGIN, ctx.y, ctx.regular, 8.5, INK_MUTED);

  if (lines.rate) {
    ctx.y -= 11;
    drawLeft(
      ctx,
      // Bounded, because the dated/recorded pair occupies the right third of
      // this block and a long rate sentence would otherwise run into it.
      fit(
        lines.rate + (opening.rate_is_manual ? '  \u00b7  rate entered by hand' : ''),
        ctx.regular,
        8,
        CONTENT_WIDTH - 230,
      ),
      MARGIN,
      ctx.y,
      ctx.regular,
      8,
      INK_FAINT,
    );
  }

  // Dated, and recorded — two different facts, and a statement needs both.
  // The label is placed relative to the width of its own value rather than at a
  // fixed offset: "20 Aug 2026 at 03:30 PM" is wide enough that a fixed one ran
  // the word "Recorded" straight through the middle of it.
  labelledRight(ctx, 'Dated', lines.dated, ctx.y + 26);
  labelledRight(ctx, 'Recorded', lines.recorded, ctx.y + 13);

  ctx.y -= 14;
  drawLeft(
    ctx,
    'Counted in the current position above. Not a credit or a debit, and not settled on its own.',
    MARGIN,
    ctx.y,
    ctx.regular,
    7.5,
    INK_FAINT,
  );
  ctx.y -= 24;
}

function drawTableHead(ctx: Ctx) {
  const y = ctx.y;
  drawLeft(ctx, 'DATE', MARGIN + COLUMNS.date.x, y, ctx.bold, 7.5, INK_FAINT);
  drawLeft(ctx, 'TYPE', MARGIN + COLUMNS.type.x, y, ctx.bold, 7.5, INK_FAINT);
  drawLeft(ctx, 'DESCRIPTION', MARGIN + COLUMNS.description.x, y, ctx.bold, 7.5, INK_FAINT);
  drawRight(
    ctx,
    'AMOUNT',
    MARGIN + COLUMNS.original.x + COLUMNS.original.width,
    y,
    ctx.bold,
    7.5,
    INK_FAINT,
  );
  drawRight(
    ctx,
    'EQUIVALENT',
    MARGIN + COLUMNS.equivalent.x + COLUMNS.equivalent.width,
    y,
    ctx.bold,
    7.5,
    INK_FAINT,
  );
  drawRight(
    ctx,
    'BALANCE',
    MARGIN + COLUMNS.balance.x + COLUMNS.balance.width,
    y,
    ctx.bold,
    7.5,
    INK_FAINT,
  );
  ctx.y -= 6;
  rule(ctx, ctx.y);
  ctx.y -= 14;
}

function drawTable(
  ctx: Ctx,
  rows: StatementRow[],
  currency: string,
  baseCurrency: string,
  truncated: boolean,
) {
  ensure(ctx, 80);
  drawLeft(ctx, 'REGULAR TRANSACTIONS', MARGIN, ctx.y, ctx.bold, 8, INK_FAINT);
  drawRight(
    ctx,
    'Credits, debits, transfers and settlements',
    PAGE_WIDTH - MARGIN,
    ctx.y,
    ctx.regular,
    8,
    INK_FAINT,
  );
  ctx.y -= 6;
  rule(ctx, ctx.y);
  ctx.y -= 16;

  if (rows.length === 0) {
    drawLeft(ctx, 'No transactions on this account.', MARGIN, ctx.y, ctx.regular, 9, INK_MUTED);
    ctx.y -= 22;
    return;
  }

  drawTableHead(ctx);

  rows.forEach((row, index) => {
    const height = row.rate ? 30 : 23;
    if (ctx.y - height < MARGIN + 44) {
      newPage(ctx);
      drawTableHead(ctx);
    }

    if (index % 2 === 1) {
      // Spans exactly this row's band: from 10pt above its first baseline down
      // to 10pt above the next one. Getting this wrong is not cosmetic — the
      // first version reached 15pt above the baseline, so every shaded row
      // painted over the *previous* row's time line and the clock times
      // silently disappeared from half the statement.
      ctx.page.drawRectangle({
        x: MARGIN - 4,
        y: ctx.y - height + 10,
        width: CONTENT_WIDTH + 8,
        height,
        color: SUNKEN,
      });
    }

    const y = ctx.y;
    drawLeft(ctx, row.date, MARGIN + COLUMNS.date.x, y, ctx.regular, 8.5, row.isVoid ? INK_FAINT : INK);
    if (row.time) {
      drawLeft(ctx, row.time, MARGIN + COLUMNS.date.x, y - 9, ctx.regular, 7, INK_FAINT);
    }

    drawLeft(
      ctx,
      fit(row.type, ctx.bold, 8.5, COLUMNS.type.width),
      MARGIN + COLUMNS.type.x,
      y,
      ctx.bold,
      8.5,
      row.isVoid ? INK_FAINT : INK,
    );
    if (row.isVoid) {
      drawLeft(ctx, 'Retracted', MARGIN + COLUMNS.type.x, y - 9, ctx.regular, 7, PAYABLE);
    }

    drawLeft(
      ctx,
      fit(row.description, ctx.regular, 8.5, COLUMNS.description.width),
      MARGIN + COLUMNS.description.x,
      y,
      ctx.regular,
      8.5,
      INK_MUTED,
    );

    // The original amount leads; the equivalent sits in its own column so a
    // reader never has to decide which of two figures is the real one.
    drawRight(
      ctx,
      fit(row.original, ctx.bold, 8.5, COLUMNS.original.width),
      MARGIN + COLUMNS.original.x + COLUMNS.original.width,
      y,
      ctx.bold,
      8.5,
      row.isVoid ? INK_FAINT : INK,
    );
    if (row.equivalent) {
      drawRight(
        ctx,
        fit(row.equivalent, ctx.regular, 8, COLUMNS.equivalent.width),
        MARGIN + COLUMNS.equivalent.x + COLUMNS.equivalent.width,
        y,
        ctx.regular,
        8,
        INK_FAINT,
      );
    }
    drawRight(
      ctx,
      fit(row.balance, ctx.regular, 8, COLUMNS.balance.width),
      MARGIN + COLUMNS.balance.x + COLUMNS.balance.width,
      y,
      ctx.regular,
      8,
      row.isVoid ? INK_FAINT : row.balanceReceivable ? RECEIVABLE : PAYABLE,
    );

    if (row.rate) {
      drawLeft(
        ctx,
        fit(row.rate, ctx.regular, 7, CONTENT_WIDTH - COLUMNS.description.x),
        MARGIN + COLUMNS.description.x,
        y - 9,
        ctx.regular,
        7,
        INK_FAINT,
      );
    }

    ctx.y -= height;
  });

  rule(ctx, ctx.y + 8);
  ctx.y -= 6;

  if (truncated) {
    drawLeft(
      ctx,
      'Older entries exist on this account and are not listed here. The balance column is carried forward from them.',
      MARGIN,
      ctx.y,
      ctx.regular,
      7.5,
      INK_FAINT,
    );
    ctx.y -= 12;
  }

  drawLeft(
    ctx,
    currency === baseCurrency
      ? 'Amounts are shown in the currency they were entered in. Balances are in the account currency.'
      : `Amounts are shown in the currency they were entered in. Balances are in ${currency}; equivalents are conversions into ${baseCurrency}.`,
    MARGIN,
    ctx.y,
    ctx.regular,
    7.5,
    INK_FAINT,
  );
  ctx.y -= 24;
}

/**
 * The four lifetime figures, straight off `person_balances`.
 *
 * The credit/debit labels are the ones the person page uses, which are the
 * reverse of the stored enum names — see lib/direction.ts and
 * docs/accounting-direction.md. Getting this pair the wrong way round in an
 * export would be the single most misleading thing this file could do.
 */
function drawTotals(ctx: Ctx, data: PersonPage, currency: string) {
  ensure(ctx, 68);
  const balance = data.balance;

  drawLeft(ctx, 'TOTALS', MARGIN, ctx.y, ctx.bold, 8, INK_FAINT);
  ctx.y -= 6;
  rule(ctx, ctx.y);
  ctx.y -= 16;

  const cells: Array<{ label: string; value: string; color: ReturnType<typeof rgb> }> = [
    { label: 'Credited to you', value: pdfMoney(balance.total_debit, currency), color: PAYABLE },
    { label: 'Debited to them', value: pdfMoney(balance.total_credit, currency), color: RECEIVABLE },
    { label: 'Settled', value: pdfMoney(balance.total_settled, currency), color: INK },
    {
      label: 'Current position',
      value: pdfMoney(Math.abs(balance.net_balance), currency, { compactDecimals: false }),
      color:
        balanceTone(balance.net_balance) === 'receivable'
          ? RECEIVABLE
          : balanceTone(balance.net_balance) === 'payable'
            ? PAYABLE
            : INK,
    },
  ];

  const cellWidth = CONTENT_WIDTH / cells.length;
  cells.forEach((cell, index) => {
    const x = MARGIN + cellWidth * index;
    drawLeft(ctx, cell.label, x, ctx.y, ctx.regular, 8, INK_MUTED);
    drawLeft(
      ctx,
      fit(cell.value, ctx.bold, 11, cellWidth - 8),
      x,
      ctx.y - 14,
      ctx.bold,
      11,
      cell.color,
    );
  });

  ctx.y -= 34;
  drawLeft(
    ctx,
    'The current position includes the opening balance shown above, every entry listed, and every settlement.',
    MARGIN,
    ctx.y,
    ctx.regular,
    7.5,
    INK_FAINT,
  );
}

/**
 * Footer on every page, written last so it can say "of N".
 *
 * Two lines: what the document is and which page this is, then the copyright.
 * The year comes from the clock rather than a literal, so a statement exported
 * next January does not claim to be this year's.
 */
function paginate(ctx: Ctx, personName: string) {
  const pages = ctx.doc.getPages();
  const year = new Date().getFullYear();
  const copyright = drawable(
    `\u00a9 ${year} ${PUBLISHER}. Accounic and this statement are its work.`,
  );

  pages.forEach((page, index) => {
    const label = `Page ${index + 1} of ${pages.length}`;
    const name = drawable(`${personName} \u2014 Accounic statement`);

    page.drawLine({
      start: { x: MARGIN, y: MARGIN + 26 },
      end: { x: PAGE_WIDTH - MARGIN, y: MARGIN + 26 },
      thickness: 0.5,
      color: LINE,
    });

    page.drawText(fit(name, ctx.regular, 7.5, CONTENT_WIDTH - 90), {
      x: MARGIN,
      y: MARGIN + 15,
      size: 7.5,
      font: ctx.regular,
      color: INK_FAINT,
    });
    const width = ctx.regular.widthOfTextAtSize(label, 7.5);
    page.drawText(label, {
      x: PAGE_WIDTH - MARGIN - width,
      y: MARGIN + 15,
      size: 7.5,
      font: ctx.regular,
      color: INK_FAINT,
    });

    page.drawText(fit(copyright, ctx.regular, 7, CONTENT_WIDTH - 120), {
      x: MARGIN,
      y: MARGIN + 5,
      size: 7,
      font: ctx.regular,
      color: INK_FAINT,
    });
    const homeWidth = ctx.regular.widthOfTextAtSize(PRODUCT_HOME, 7);
    page.drawText(PRODUCT_HOME, {
      x: PAGE_WIDTH - MARGIN - homeWidth,
      y: MARGIN + 5,
      size: 7,
      font: ctx.regular,
      color: INK_FAINT,
    });
  });
}
