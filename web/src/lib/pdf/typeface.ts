import 'server-only';

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import fontkit from '@pdf-lib/fontkit';

/**
 * The typeface a statement is set in, and the one thing it cannot do.
 *
 * Accounic is set in Poppins on every screen, so a PDF that came out of it in
 * Helvetica would not look like the same product. Poppins is also the reason
 * this module exists at all: the fourteen fonts every PDF reader has built in
 * are WinAnsi-encoded, and WinAnsi has no rupee sign. A rupee ledger exported
 * in Helvetica prints `10,393.69` with a blank where the ₹ should be, or
 * refuses to encode the string at all.
 *
 * Embedding Poppins fixes ₹ — and $, €, £, ¥, ₨, ₺, ₽, zł, Kč and Devanagari,
 * which is most of what this product's currency list uses. It does not fix all
 * of it: ₪, ₫, ₩, ₦, ₱, ৳ and ฿ have no glyph in Poppins, and asking pdf-lib to
 * draw one of those throws rather than degrading.
 *
 * So the font's own character set is the authority here, read once at startup,
 * and `supportsAll()` is what every caller asks before printing anything. What
 * a caller does about an unsupported character is its own decision —
 * `lib/pdf/money.ts` drops the symbol and keeps the ISO code, which is
 * unambiguous and always printable.
 */

const FONT_DIR = join(process.cwd(), 'src', 'lib', 'pdf', 'fonts');

export interface Typeface {
  regular: Uint8Array;
  bold: Uint8Array;
}

let cached: Typeface | null = null;
let coverage: Set<number> | null = null;

export function loadTypeface(): Typeface {
  if (cached) return cached;
  cached = {
    regular: new Uint8Array(readFileSync(join(FONT_DIR, 'Poppins-Medium.ttf'))),
    bold: new Uint8Array(readFileSync(join(FONT_DIR, 'Poppins-SemiBold.ttf'))),
  };
  return cached;
}

/**
 * Which code points the embedded face can actually draw.
 *
 * Probed rather than hard-coded: a hard-coded list is a second source of truth
 * that goes stale the moment the font file is replaced, and the failure mode of
 * a stale list is a thrown exception in the middle of generating somebody's
 * statement.
 */
function characterSet(): Set<number> {
  if (coverage) return coverage;
  const font = fontkit.create(Buffer.from(loadTypeface().regular)) as {
    hasGlyphForCodePoint?: (codePoint: number) => boolean;
    characterSet?: number[];
  };

  const set = new Set<number>();
  if (Array.isArray(font.characterSet)) {
    for (const code of font.characterSet) set.add(code);
  }
  coverage = set;
  return coverage;
}

/** True when every character in `text` has a glyph in the embedded face. */
export function supportsAll(text: string): boolean {
  const set = characterSet();
  // An empty character set means the probe failed, not that the font is empty.
  // Answering "no" then would strip every symbol from every statement, so the
  // safer wrong answer is the one that keeps the export looking right.
  if (set.size === 0) return true;

  for (const rune of text) {
    const code = rune.codePointAt(0);
    if (code === undefined) continue;
    // Whitespace is always drawable and is not always in the cmap.
    if (code === 0x20 || code === 0x0a || code === 0x09) continue;
    if (!set.has(code)) return false;
  }
  return true;
}

/**
 * `text` with anything the face cannot draw removed.
 *
 * For names and notes, which can hold anything a user typed. Dropping is better
 * than substituting a box or a question mark: a statement that says "Rahul"
 * where the name was "Rahul ☂" is still true, and one that says "Rahul ?" looks
 * like a defect. A string that empties completely becomes an em dash, so a
 * column never silently collapses.
 */
export function drawable(text: string, fallback = '—'): string {
  if (supportsAll(text)) return text;
  let out = '';
  for (const rune of text) {
    if (supportsAll(rune)) out += rune;
  }
  const trimmed = out.replace(/\s+/g, ' ').trim();
  return trimmed === '' ? fallback : trimmed;
}
