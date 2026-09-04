import 'server-only';

import { PDFDocument, rgb, type PDFFont, type PDFPage } from 'pdf-lib';
import fontkit from '@pdf-lib/fontkit';

import { drawable, loadTypeface } from '@/lib/pdf/typeface';
import { pdfActivityApprox, pdfActivityMoney } from '@/lib/pdf/money';
import { buildActivityReport, type ActivityReport, type ActivityReportRow } from '@/lib/export/activity-report';
import { statementDate } from '@/lib/dates';
import type { ActivityRange, ActivityView } from '@/lib/export/activity';
import type { ExportBundle } from '@/lib/export/types';

/**
 * The Activity feed, as a PDF.
 *
 * The document a person expects when they press Export on the Activity screen:
 * the same page, typeset. A day heading with its entry count, a rule under it,
 * then the entries of that day — account, what kind of entry, the amount as it
 * was entered — then the next day.
 *
 * It is deliberately a different document from `lib/pdf/workspace.ts`, which
 * groups the same rows by account and opens with the workspace position. That
 * one answers "where does each account stand?"; this one answers "what
 * happened, and when?", and a reader should be able to lay it beside the screen
 * and find the same rows in the same order.
 *
 * The same rule as every other writer here: **it computes no money.** Every
 * string below came out of `lib/export/activity-report.ts`, which only formats
 * figures the database returned.
 *
 * Mirrored by `app/lib/data/activity_pdf.dart`.
 */

const PAGE_WIDTH = 595.28; // A4 portrait, points
const PAGE_HEIGHT = 841.89;
const MARGIN = 36;
const CONTENT = PAGE_WIDTH - MARGIN * 2;
const BOTTOM = 54;

const INK = rgb(0.08, 0.09, 0.1);
const MUTED = rgb(0.42, 0.45, 0.5);
const FAINT = rgb(0.58, 0.61, 0.65);
const LINE = rgb(0.89, 0.9, 0.92);
const BRAND = rgb(0.145, 0.388, 0.921);
const RECEIVABLE = rgb(0.067, 0.502, 0.29);
const PAYABLE = rgb(0.706, 0.137, 0.169);

/** Anything outside Basic Latin and its extensions — the shaper's danger zone. */
const NON_LATIN = /[^ -ɏ]/g;

/** The amount column, right-aligned; everything else flows in what is left. */
const AMOUNT_WIDTH = 150;
const BODY_WIDTH = CONTENT - AMOUNT_WIDTH - 12;

interface Cursor {
  page: PDFPage;
  y: number;
}

interface Fonts {
  regular: PDFFont;
  bold: PDFFont;
}

export async function renderActivityPdf(
  bundle: ExportBundle,
  options: { view: ActivityView; range: ActivityRange },
): Promise<Uint8Array> {
  const report = buildActivityReport(
    bundle,
    { money: pdfActivityMoney, approx: pdfActivityApprox },
    options,
  );

  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);
  const typeface = loadTypeface();
  const fonts: Fonts = {
    regular: await doc.embedFont(typeface.regular, { subset: true }),
    bold: await doc.embedFont(typeface.bold, { subset: true }),
  };

  doc.setTitle(`${report.workspaceName} — activity report`);
  doc.setAuthor(report.ownerName ?? report.workspaceName);
  doc.setCreator('Accounic');

  const cursor: Cursor = { page: doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]), y: PAGE_HEIGHT - MARGIN };

  drawCover(cursor, fonts, report);
  drawDays(doc, cursor, fonts, report);
  paginate(doc, fonts, report);

  return doc.save();
}

/* -------------------------------------------------------------------------- */
/* Primitives                                                                  */
/* -------------------------------------------------------------------------- */

function measure(value: string, font: PDFFont, size: number): number | null {
  // fontkit runs full shaping to measure, and that throws on some scripts in
  // some runtimes. A failed measurement must not take the export down.
  try {
    return font.widthOfTextAtSize(value, size);
  } catch {
    return null;
  }
}

function text(
  cursor: Cursor,
  value: string,
  options: {
    x?: number;
    size?: number;
    font: PDFFont;
    color?: ReturnType<typeof rgb>;
    width?: number;
    align?: 'left' | 'right';
  },
): void {
  const size = options.size ?? 9;
  const safe = drawable(value);
  if (safe === '') return;

  const measured = measure(safe, options.font, size) ?? safe.length * size * 0.55;
  const x =
    options.align === 'right'
      ? (options.x ?? MARGIN) + (options.width ?? 0) - measured
      : (options.x ?? MARGIN);

  try {
    cursor.page.drawText(safe, {
      x,
      y: cursor.y,
      size,
      font: options.font,
      color: options.color ?? INK,
    });
  } catch {
    // One name the shaper cannot handle must not cost the whole export.
    const ascii = safe.replace(NON_LATIN, '').trim();
    if (ascii === '') return;
    cursor.page.drawText(ascii, {
      x,
      y: cursor.y,
      size,
      font: options.font,
      color: options.color ?? INK,
    });
  }
}

function ensureRoom(doc: PDFDocument, cursor: Cursor, needed: number): void {
  if (cursor.y - needed > BOTTOM) return;
  cursor.page = doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]);
  cursor.y = PAGE_HEIGHT - MARGIN;
}

function rule(cursor: Cursor, color = LINE): void {
  cursor.page.drawLine({
    start: { x: MARGIN, y: cursor.y },
    end: { x: PAGE_WIDTH - MARGIN, y: cursor.y },
    thickness: 0.5,
    color,
  });
}

/** Truncate to fit a column, with an ellipsis when it does not. */
function fit(value: string, font: PDFFont, size: number, width: number): string {
  const safe = drawable(value);
  const measured = measure(safe, font, size);

  if (measured === null) {
    const perChar = size * 0.55;
    const max = Math.max(1, Math.floor(width / perChar));
    return safe.length <= max ? safe : `${safe.slice(0, max - 1)}…`;
  }
  if (measured <= width) return safe;

  let cut = safe;
  for (;;) {
    if (cut.length <= 1) break;
    const next = measure(`${cut}…`, font, size);
    if (next === null || next <= width) break;
    cut = cut.slice(0, -1);
  }
  return `${cut}…`;
}

/* -------------------------------------------------------------------------- */
/* Sections                                                                    */
/* -------------------------------------------------------------------------- */

function drawCover(cursor: Cursor, fonts: Fonts, report: ActivityReport): void {
  cursor.y -= 14;
  text(cursor, report.workspaceName, { font: fonts.bold, size: 19 });
  cursor.y -= 14;
  text(cursor, report.title, { font: fonts.regular, size: 11, color: BRAND });

  cursor.y -= 14;
  rule(cursor);
  cursor.y -= 18;

  const left = [
    ['Showing', report.scope],
    ['Category', report.category],
    ['Base currency', report.baseCurrency],
  ] as const;

  const right = [
    ['Generated', statementDate(report.exportedAt.slice(0, 10))],
    ['Entries', String(report.counts.entries)],
    ['Days', String(report.counts.days)],
  ] as const;

  const top = cursor.y;
  const half = CONTENT / 2 - 8;

  for (const [label, value] of left) {
    text(cursor, label.toUpperCase(), { font: fonts.regular, size: 7, color: MUTED });
    cursor.y -= 11;
    text(cursor, fit(value, fonts.regular, 9.5, half), { font: fonts.regular, size: 9.5 });
    cursor.y -= 16;
  }

  const leftBottom = cursor.y;
  cursor.y = top;

  for (const [label, value] of right) {
    text(cursor, label.toUpperCase(), {
      font: fonts.regular,
      size: 7,
      color: MUTED,
      x: MARGIN + CONTENT / 2 + 8,
    });
    cursor.y -= 11;
    text(cursor, fit(value, fonts.regular, 9.5, half), {
      font: fonts.regular,
      size: 9.5,
      x: MARGIN + CONTENT / 2 + 8,
    });
    cursor.y -= 16;
  }

  cursor.y = Math.min(leftBottom, cursor.y);

  if (report.truncated) {
    // Stated, never hidden: a file holding the first slice of a long feed must
    // not look like the whole of it.
    cursor.y -= 2;
    text(
      cursor,
      'This export reached its size limit. Older entries are not included.',
      { font: fonts.regular, size: 8.5, color: PAYABLE },
    );
    cursor.y -= 16;
  }
}

function drawDays(
  doc: PDFDocument,
  cursor: Cursor,
  fonts: Fonts,
  report: ActivityReport,
): void {
  if (report.days.length === 0) {
    cursor.y -= 8;
    text(cursor, 'No entries in this view.', { font: fonts.regular, size: 10, color: MUTED });
    return;
  }

  for (const day of report.days) {
    // A day heading is worth nothing at the foot of a page: keep it with at
    // least its first entry.
    ensureRoom(doc, cursor, 84);

    cursor.y -= 10;
    // One label, the screen's own. Printing "28 AUGUST" beside "28 August
    // 2026" said the same thing twice; the year is on the cover.
    text(cursor, day.label.toUpperCase(), {
      font: fonts.bold,
      size: 9,
      color: INK,
      // Tracked out a little, the way the screen sets its day headings.
      x: MARGIN,
    });
    text(cursor, `${day.count} ${day.count === 1 ? 'entry' : 'entries'}`, {
      font: fonts.regular,
      size: 8,
      color: MUTED,
      x: MARGIN,
      width: CONTENT,
      align: 'right',
    });

    cursor.y -= 7;
    rule(cursor);
    cursor.y -= 14;

    for (const row of day.rows) {
      drawRow(doc, cursor, fonts, row);
    }

    cursor.y -= 8;
  }
}

/**
 * One entry.
 *
 * The screen's three levels, kept: the account, then what kind of entry and its
 * note, then — quietest — the rate that explains the conversion. The amount as
 * entered leads on the right, with the base equivalent beneath it.
 */
function drawRow(
  doc: PDFDocument,
  cursor: Cursor,
  fonts: Fonts,
  row: ActivityReportRow,
): void {
  const tone = row.isSettlement ? FAINT : row.receivable ? RECEIVABLE : PAYABLE;
  const detail = [row.type, row.description].filter(Boolean).join(' · ');
  const meta = [row.rate, row.rateNote].filter(Boolean).join(' · ');
  const bodyX = MARGIN + 10;
  const amountX = MARGIN + BODY_WIDTH + 12;

  /**
   * The row as two columns of stacked lines.
   *
   * Written as stacks rather than as free drawing because the two columns used
   * to be positioned independently: the converted amount and the settlement
   * status were each placed on "the second line", which on a converted,
   * part-settled row was the same line — and they overlapped. Advancing one
   * cursor down a pair of stacks makes that impossible to reintroduce.
   */
  type Line = { value: string; size: number; color: ReturnType<typeof rgb>; bold?: boolean };

  const left: Line[] = [
    { value: fit(row.person, fonts.bold, 9.5, BODY_WIDTH), size: 9.5, color: INK, bold: true },
  ];
  if (detail) {
    left.push({ value: fit(detail, fonts.regular, 8.5, BODY_WIDTH), size: 8.5, color: MUTED });
  }
  if (meta) {
    left.push({ value: fit(meta, fonts.regular, 7.5, BODY_WIDTH), size: 7.5, color: FAINT });
  }

  const right: Line[] = [
    {
      value: row.amount,
      size: 9.5,
      color: row.isSettlement ? INK : tone,
      bold: true,
    },
  ];
  if (row.equivalent) right.push({ value: row.equivalent, size: 8, color: MUTED });
  if (row.settlement) right.push({ value: row.settlement, size: 8, color: FAINT });

  // The leading between lines, by which line it leads into. Unchanged from the
  // spacing the row already had; the fix is that both columns now use it.
  const LEADING = [0, 11, 10, 10];
  const lines = Math.max(left.length, right.length);
  let height = 12;
  for (let i = 1; i < lines; i += 1) height += LEADING[i] ?? 10;
  height += 8;

  ensureRoom(doc, cursor, height);

  // The tint the screen puts behind the glyph, here as a 2pt spine beside the
  // row: settlement neutral, everything else coloured by which way the debt
  // runs. It is the cheapest way to keep the feed scannable on paper.
  cursor.page.drawRectangle({
    x: MARGIN,
    y: cursor.y - (height - 14),
    width: 2,
    height: height - 6,
    color: tone,
  });

  for (let i = 0; i < lines; i += 1) {
    if (i > 0) cursor.y -= LEADING[i] ?? 10;

    const l = left[i];
    if (l) {
      text(cursor, l.value, {
        font: l.bold ? fonts.bold : fonts.regular,
        size: l.size,
        color: l.color,
        x: bodyX,
      });
    }

    const r = right[i];
    if (r) {
      text(cursor, r.value, {
        font: r.bold ? fonts.bold : fonts.regular,
        size: r.size,
        color: r.color,
        x: amountX,
        width: AMOUNT_WIDTH,
        align: 'right',
      });
    }
  }

  cursor.y -= 8;
  // A hairline between entries, not a box around each: the feed reads as one
  // column of events, which is what it is.
  rule(cursor, rgb(0.945, 0.95, 0.957));
  cursor.y -= 10;
}

function paginate(doc: PDFDocument, fonts: Fonts, report: ActivityReport): void {
  const pages = doc.getPages();

  pages.forEach((page, index) => {
    const footer = drawable(
      `Generated by Accounic · ${statementDate(report.exportedAt.slice(0, 10))}`,
    );
    page.drawText(footer, { x: MARGIN, y: 28, size: 7, font: fonts.regular, color: MUTED });

    const label = drawable(`Page ${index + 1} of ${pages.length}`);
    page.drawText(label, {
      x: PAGE_WIDTH - MARGIN - (measure(label, fonts.regular, 7) ?? 40),
      y: 28,
      size: 7,
      font: fonts.regular,
      color: MUTED,
    });

    if (index > 0) {
      const running =
        drawable(report.workspaceName).replace(NON_LATIN, '').trim() || 'Accounic';
      page.drawText(running, {
        x: MARGIN,
        y: PAGE_HEIGHT - 24,
        size: 7.5,
        font: fonts.regular,
        color: MUTED,
      });
      const right = drawable(`Activity report · ${report.category}`);
      page.drawText(right, {
        x: PAGE_WIDTH - MARGIN - (measure(right, fonts.regular, 7.5) ?? 80),
        y: PAGE_HEIGHT - 24,
        size: 7.5,
        font: fonts.regular,
        color: MUTED,
      });
    }
  });
}
