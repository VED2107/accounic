/**
 * Appearance (context.md §18).
 *
 * Accounic is dark-first — that is the product's face — but a ledger is read for
 * long stretches in whatever light the reader happens to be in, so the choice is
 * theirs. Three states: follow the system, or pin one.
 *
 * The chosen value is written to `data-theme` on <html>; globals.css keys the
 * whole palette off it. Nothing else in the app knows a theme exists.
 */

export type ThemeChoice = 'system' | 'light' | 'dark';

export const THEME_KEY = 'accounic:theme';
export const THEME_EVENT = 'accounic:theme-change';

/**
 * Runs before first paint, inlined in the document head. Without it the page
 * paints the default dark palette and then swaps, which is a flash on every
 * navigation for anyone who chose light.
 */
export const THEME_BOOT_SCRIPT = `(function(){try{var t=localStorage.getItem('${THEME_KEY}');if(t==='light'||t==='dark'){document.documentElement.dataset.theme=t}}catch(e){}})();`;

export function readTheme(): ThemeChoice {
  if (typeof window === 'undefined') return 'system';
  const stored = window.localStorage.getItem(THEME_KEY);
  return stored === 'light' || stored === 'dark' ? stored : 'system';
}

export function applyTheme(choice: ThemeChoice): void {
  const root = document.documentElement;
  if (choice === 'system') {
    delete root.dataset.theme;
    window.localStorage.removeItem(THEME_KEY);
  } else {
    root.dataset.theme = choice;
    window.localStorage.setItem(THEME_KEY, choice);
  }
  // Anything else on screen showing the current choice updates itself.
  window.dispatchEvent(new CustomEvent(THEME_EVENT, { detail: choice }));
}
