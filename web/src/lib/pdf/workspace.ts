import 'server-only';

import { PDFDocument, rgb, type PDFFont, type PDFPage } from 'pdf-lib';
import fontkit from '@pdf-lib/fontkit';

import { drawable, loadTypeface } from '@/lib/pdf/typeface';
import { pdfApprox, pdfMoney } from '@/lib/pdf/money';
import { buildWorkspaceReport, type ReportRow, type WorkspaceReport } from '@/lib/export/report';
import { statementDate } from '@/lib/dates';
import type { ExportBundle } from '@/lib/export/types';

/**
 * The workspace accounting export, as a PDF (Phase 4).
 *
 * The same rule that governs `lib/pdf/statement.ts` governs this file: **it
 * computes no money.** Every string below came out of `lib/export/report.ts`,
 * which in turn only formats numbers the database returned. There is no
 * arithmetic here and no second idea of what a credit is.
 *
 * It is a different document from the account statement, deliberately:
 *
 *     Cover      who, when, what period, which filters, how many entries
 *     Position   the workspace position PER CURRENCY, never summed across
 *     Accounts   every person with their balances
 *     Ledger     each account's entries, opening balances in their own block
 *
 * The account statement is untouched and still reached from a person's page.
 *
 * Layout is hand-set, as it is there: pdf-lib draws text at coordinates and
 * measures strings, so column positions, row heights and page breaks are
 * decided here and nowhere else. The Flutter client draws the same document
 * with the `pdf` package's flow layout — same sections, same order, same words.
 */

const PAGE_WIDTH = 595.28; // A4 portrait, points
const PAGE_HEIGHT = 841.89;
const MARGIN = 36;
const CONTENT = PAGE_WIDTH - MARGIN * 2;
const BOTTOM = 54;

const INK = rgb(0.08, 0.09, 0.1);
const MUTED = rgb(0.42, 0.45, 0.5);
const LINE = rgb(0.89, 0.9, 0.92);
const BAND = rgb(0.965, 0.97, 0.976);
const BRAND = rgb(0.145, 0.388, 0.921);
const RECEIVABLE = rgb(0.067, 0.502, 0.29);
const PAYABLE = rgb(0.706, 0.137, 0.169);

/** Anything outside Basic Latin and its extensions — the shaper's danger zone. */
const NON_LATIN = /[^ -ɏ]/g;

interface Cursor {
  page: PDFPage;
  y: number;
}

interface Fonts {
  regular: PDFFont;
  bold: PDFFont;
}

interface Column {
  label: string;
  width: number;
  align?: 'left' | 'right';
}

export async function renderWorkspacePdf(bundle: ExportBundle): Promise<Uint8Array> {
  const report = buildWorkspaceReport(bundle, { money: pdfMoney, approx: pdfApprox });

  const doc = await PDFDocument.create();
  doc.registerFontkit(fontkit);
  const typeface = loadTypeface();
  const fonts: Fonts = {
    regular: await doc.embedFont(typeface.regular, { subset: true }),
    bold: await doc.embedFont(typeface.bold, { subset: true }),
  };

  doc.setTitle(`${report.workspaceName} — accounting export`);
  doc.setAuthor(report.ownerName ?? report.workspaceName);
  doc.setCreator('Accounic');

  const cursor: Cursor = { page: doc.addPage([PAGE_WIDTH, PAGE_HEIGHT]), y: PAGE_HEIGHT - MARGIN };

  drawCover(cursor, fonts, report);
  drawPositions(doc, cursor, fonts, report);
  drawAccounts(doc, cursor, fonts, report);
  drawLedger(doc, cursor, fonts, report);

  paginate(doc, fonts, report);

  return doc.save();
}

/* -------------------------------------------------------------------------- */
/* Primitives                                                                  */
/* -------------------------------------------------------------------------- */

function text(
  cursor: Cursor,
  value: string,
  options: {
    x?: number;
    size?: number;
    font?: PDFFont;
    color?: ReturnType<typeof rgb>;
    width?: number;
    align?: 'left' | 'right';
  },
): void {
  const font = options.font!;
  const size = options.size ?? 9;
  // `drawable` drops anything the embedded face cannot draw rather than letting
  // pdf-lib throw in the middle of somebody's export.
  const safe = drawable(value);
  const measured = measure(safe, font, size) ?? safe.length * size * 0.55;
  const x =
    options.align === 'right'
      ? (options.x ?? MARGIN) + (options.width ?? 0) - measured
      : (options.x ?? MARGIN);

  try {
    cursor.page.drawText(safe, { x, y: cursor.y, size, font, color: options.color ?? INK });
  } catch {
    // The same shaping failure as above, this time while drawing. One name the
    // shaper cannot handle must not cost the user their whole export, so the
    // cell falls back to what can be drawn and the rest of the file stands.
    const ascii = safe.replace(NON_LATIN, '').trim();
    if (ascii === '') return;
    cursor.page.drawText(ascii, { x, y: cursor.y, size, font, color: options.color ?? INK });
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

/**
 * How wide a string is, or null when the shaper cannot answer.
 *
 * fontkit runs full complex-script shaping to measure a string, and that path
 * throws on some scripts in some runtimes (Devanagari is the one this product
 * meets). A thrown measurement must not take the whole export down, so the
 * caller gets null and falls back to an estimate.
 */
function measure(value: string, font: PDFFont, size: number): number | null {
  try {
    return font.widthOfTextAtSize(value, size);
  } catch {
    return null;
  }
}

/** Truncate to fit a column, with an ellipsis when it does not. */
function fit(value: string, font: PDFFont, size: number, width: number): string {
  const safe = drawable(value);
  const measured = measure(safe, font, size);

  if (measured === null) {
    // No shaper: assume the average glyph is ~0.55em, which errs towards
    // cutting slightly early rather than overrunning the column.
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

function drawCover(cursor: Cursor, fonts: Fonts, report: WorkspaceReport): void {
  cursor.y -= 14;
  text(cursor, report.workspaceName, { font: fonts.bold, size: 19 });
  cursor.y -= 14;
  text(cursor, report.title, { font: fonts.regular, size: 11, color: BRAND });

  cursor.y -= 14;
  rule(cursor);
  cursor.y -= 18;

  const left = [
    ['Period', report.period],
    ['Contents', report.filters],
    ['Base currency', report.baseCurrency],
  ] as const;

  const right = [
    ['Generated', statementDate(report.exportedAt.slice(0, 10))],
    ['Accounts', String(report.counts.people)],
    [
      'Entries',
      `${report.counts.entries} · ${report.counts.transactions} transactions, ${report.counts.settlements} settlements`,
    ],
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
    cursor.y -= 6;
    cursor.page.drawRectangle({
      x: MARGIN,
      y: cursor.y - 20,
      width: CONTENT,
      height: 28,
      color: BAND,
      borderColor: PAYABLE,
      borderWidth: 0.5,
    });
    cursor.y -= 8;
    text(
      cursor,
      `This export reached its size limit and holds the first ${report.counts.entries} entries.`,
      { font: fonts.regular, size: 8.5, color: PAYABLE, x: MARGIN + 8 },
    );
    cursor.y -= 12;
    text(cursor, 'Narrow the period, or export one account at a time.', {
      font: fonts.regular,
      size: 8.5,
      color: PAYABLE,
      x: MARGIN + 8,
    });
    cursor.y -= 18;
  }
}

function sectionTitle(
  doc: PDFDocument,
  cursor: Cursor,
  fonts: Fonts,
  title: string,
  subtitle: string,
): void {
  ensureRoom(doc, cursor, 60);
  cursor.y -= 22;
  text(cursor, title, { font: fonts.bold, size: 13 });
  cursor.y -= 11;
  text(cursor, subtitle, { font: fonts.regular, size: 8, color: MUTED });
  cursor.y -= 12;
}

function headerRow(cursor: Cursor, fonts: Fonts, columns: Column[]): void {
  cursor.page.drawRectangle({
    x: MARGIN,
    y: cursor.y - 4,
    width: CONTENT,
    height: 15,
    color: BAND,
  });

  let x = MARGIN + 4;
  for (const column of columns) {
    text(cursor, column.label.toUpperCase(), {
      font: fonts.regular,
      size: 7,
      color: MUTED,
      x,
      width: column.width - 8,
      align: column.align,
    });
    x += column.width;
  }
  cursor.y -= 16;
}

function bodyRow(
  cursor: Cursor,
  fonts: Fonts,
  columns: Column[],
  cells: { value: string; color?: ReturnType<typeof rgb>; bold?: boolean }[],
): void {
  let x = MARGIN + 4;
  columns.forEach((column, index) => {
    const cell = cells[index];
    if (!cell) return;
    const font = cell.bold ? fonts.bold : fonts.regular;
    text(cursor, fit(cell.value, font, 8.5, column.width - 8), {
      font,
      size: 8.5,
      color: cell.color ?? INK,
      x,
      width: column.width - 8,
      align: column.align,
    });
    x += column.width;
  });

  cursor.y -= 5;
  rule(cursor);
  cursor.y -= 11;
}

function drawPositions(
  doc: PDFDocument,
  cursor: Cursor,
  fonts: Fonts,
  report: WorkspaceReport,
): void {
  if (report.positions.length === 0) return;

  sectionTitle(doc, cursor, fonts, 'Position', 'As it stands today, in each currency');

  const columns: Column[] = [
    { label: 'Currency', width: 70 },
    { label: 'They owe me', width: 100, align: 'right' },
    { label: 'I owe them', width: 100, align: 'right' },
    { label: 'Net', width: 100, align: 'right' },
    { label: 'Cash in hand', width: 90, align: 'right' },
    { label: 'Opening', width: CONTENT - 460, align: 'right' },
  ];

  headerRow(cursor, fonts, columns);

  for (const position of report.positions) {
    ensureRoom(doc, cursor, 24);
    bodyRow(cursor, fonts, columns, [
      { value: position.currency, bold: true },
      { value: position.receivable, color: RECEIVABLE },
      { value: position.payable, color: PAYABLE },
      {
        value: position.net,
        color: position.netReceivable ? RECEIVABLE : PAYABLE,
        bold: true,
      },
      { value: position.cash ?? '—' },
      { value: position.opening ?? '—' },
    ]);
  }
}

function drawAccounts(
  doc: PDFDocument,
  cursor: Cursor,
  fonts: Fonts,
  report: WorkspaceReport,
): void {
  if (report.people.length === 0) return;

  sectionTitle(doc, cursor, fonts, 'Accounts', 'Every person, in their own ledger currency');

  const columns: Column[] = [
    { label: 'Account', width: 150 },
    { label: 'Currency', width: 60 },
    { label: 'They owe me', width: 95, align: 'right' },
    { label: 'I owe them', width: 95, align: 'right' },
    { label: 'Net', width: 90, align: 'right' },
    { label: 'Opening', width: CONTENT - 490, align: 'right' },
  ];

  headerRow(cursor, fonts, columns);

  for (const person of report.people) {
    ensureRoom(doc, cursor, 24);
    bodyRow(cursor, fonts, columns, [
      { value: person.archived ? `${person.name} (archived)` : person.name },
      { value: person.currency },
      { value: person.receivable, color: RECEIVABLE },
      { value: person.payable, color: PAYABLE },
      { value: person.net, color: person.netReceivable ? RECEIVABLE : PAYABLE, bold: true },
      { value: person.opening ?? '—' },
    ]);
  }
}

function drawLedger(
  doc: PDFDocument,
  cursor: Cursor,
  fonts: Fonts,
  report: WorkspaceReport,
): void {
  const sections = report.sections.filter(
    (section) => section.rows.length > 0 || section.openingRows.length > 0,
  );

  if (sections.length === 0) {
    sectionTitle(doc, cursor, fonts, 'Ledger', 'No entries fall inside this export');
    return;
  }

  sectionTitle(doc, cursor, fonts, 'Ledger', 'Each account, opening balances kept apart');

  const columns: Column[] = [
    { label: 'Date', width: 70 },
    { label: 'Type', width: 95 },
    { label: 'Description', width: 160 },
    { label: 'Amount', width: 110, align: 'right' },
    { label: 'Settled', width: CONTENT - 435, align: 'right' },
  ];

  for (const section of sections) {
    ensureRoom(doc, cursor, 70);
    cursor.y -= 8;
    text(cursor, `${section.personName} · ${section.currency}`, { font: fonts.bold, size: 10.5 });
    cursor.y -= 14;

    if (section.openingRows.length > 0) {
      text(cursor, 'OPENING BALANCE', { font: fonts.regular, size: 7, color: MUTED });
      cursor.y -= 12;
      headerRow(cursor, fonts, columns);
      drawRows(doc, cursor, fonts, columns, section.openingRows);
      cursor.y -= 6;
    }

    if (section.rows.length > 0) {
      if (section.openingRows.length > 0) {
        ensureRoom(doc, cursor, 40);
        text(cursor, 'TRANSACTIONS', { font: fonts.regular, size: 7, color: MUTED });
        cursor.y -= 12;
      }
      headerRow(cursor, fonts, columns);
      drawRows(doc, cursor, fonts, columns, section.rows);
    }

    cursor.y -= 10;
  }
}

function drawRows(
  doc: PDFDocument,
  cursor: Cursor,
  fonts: Fonts,
  columns: Column[],
  rows: ReportRow[],
): void {
  for (const row of rows) {
    ensureRoom(doc, cursor, row.equivalent ? 34 : 24);

    bodyRow(cursor, fonts, columns, [
      { value: row.date },
      { value: row.isVoid ? `${row.type} (void)` : row.type },
      { value: row.description },
      { value: row.amount, color: row.isVoid ? MUTED : INK },
      { value: row.settlement ?? '—', color: MUTED },
    ]);

    if (row.equivalent) {
      cursor.y += 6;
      text(cursor, row.equivalent, {
        font: fonts.regular,
        size: 7.5,
        color: MUTED,
        x: MARGIN + 4 + columns[0]!.width + columns[1]!.width + columns[2]!.width,
        width: columns[3]!.width - 8,
        align: 'right',
      });
      cursor.y -= 12;
    }
  }
}

/** The running header and the page numbers, once every page exists. */
function paginate(doc: PDFDocument, fonts: Fonts, report: WorkspaceReport): void {
  const pages = doc.getPages();

  pages.forEach((page, index) => {
    const footer = drawable(
      `Generated by Accounic · ${statementDate(report.exportedAt.slice(0, 10))}`,
    );
    page.drawText(footer, {
      x: MARGIN,
      y: 28,
      size: 7,
      font: fonts.regular,
      color: MUTED,
    });

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
      const right = drawable('Accounting export');
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
