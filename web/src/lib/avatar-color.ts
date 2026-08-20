/**
 * A stable colour per person (context.md §18).
 *
 * Avatars used to be tinted by the balance, which meant a directory of people
 * was a wall of red and green — the two colours that are supposed to mean money
 * and nothing else. Tinting by identity instead gives each account a face you
 * recognise before you read the name, and hands red and green back to the
 * figures where they carry meaning.
 *
 * The palette deliberately avoids the receivable green and the payable red. It
 * sits in the blues, cyans, violets and warm neutrals, so no avatar can be
 * mistaken for a balance state.
 *
 * The hash is FNV-1a: stable across reloads, across the two clients, and cheap
 * enough to run per row.
 */

export interface AvatarPalette {
  /** Tinted background. */
  bg: string;
  /** The initials. */
  fg: string;
  /** Hairline border. */
  border: string;
}

/** Hue, and the lightness the initials need on each scheme. */
const HUES: Array<{ h: number; s: number }> = [
  { h: 217, s: 85 }, // brand blue
  { h: 199, s: 88 }, // sky
  { h: 188, s: 82 }, // cyan
  { h: 258, s: 74 }, // violet
  { h: 280, s: 62 }, // plum
  { h: 32, s: 88 }, //  amber
  { h: 14, s: 72 }, //  clay
  { h: 172, s: 62 }, // muted teal
  { h: 228, s: 60 }, // indigo
  { h: 205, s: 30 }, // slate
];

function hash(value: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < value.length; i++) {
    h ^= value.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/**
 * Returned as inline styles rather than classes: the hue is data, and Tailwind
 * cannot generate a class per person at build time.
 */
export function avatarPalette(name: string): AvatarPalette {
  const { h, s } = HUES[hash(name.trim().toLowerCase()) % HUES.length]!;

  // One set of values that reads on both schemes: a translucent wash for the
  // ground, a light, saturated ink on top. On the light scheme the wash is
  // barely there and the ink darkens via the alpha of the border.
  return {
    bg: `color-mix(in oklab, hsl(${h} ${s}% 55%) 16%, transparent)`,
    fg: `hsl(${h} ${Math.min(s + 5, 95)}% var(--avatar-ink, 68%))`,
    border: `color-mix(in oklab, hsl(${h} ${s}% 55%) 34%, transparent)`,
  };
}
