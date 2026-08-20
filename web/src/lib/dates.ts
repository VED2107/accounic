/**
 * Date presentation (context.md §16).
 *
 * Dates from the database are plain `YYYY-MM-DD` calendar dates with no time
 * zone. Parsing them with `new Date('2026-08-12')` would read them as UTC
 * midnight and shift them a day backwards for anyone west of Greenwich, so they
 * are split by hand and built in local time instead.
 */

export function parseDbDate(value: string): Date {
  const [y, m, d] = value.slice(0, 10).split('-').map(Number);
  return new Date(y ?? 1970, (m ?? 1) - 1, d ?? 1);
}

export function todayIso(): string {
  const now = new Date();
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

function startOfDay(date: Date): number {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

/** "Today", "Yesterday", "12 Aug", or "12 Aug 2024" once the year differs. */
export function friendlyDate(value: string): string {
  const date = parseDbDate(value);
  const now = new Date();
  const dayDiff = Math.round((startOfDay(now) - startOfDay(date)) / 86_400_000);

  if (dayDiff === 0) return 'Today';
  if (dayDiff === 1) return 'Yesterday';
  if (dayDiff === -1) return 'Tomorrow';

  const sameYear = date.getFullYear() === now.getFullYear();
  return new Intl.DateTimeFormat('en-IN', {
    day: 'numeric',
    month: 'short',
    ...(sameYear ? {} : { year: 'numeric' }),
  }).format(date);
}

export function fullDate(value: string): string {
  return new Intl.DateTimeFormat('en-IN', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  }).format(parseDbDate(value));
}

export function relativeTime(isoTimestamp: string): string {
  const then = new Date(isoTimestamp).getTime();
  const seconds = Math.round((Date.now() - then) / 1000);
  const rtf = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });

  const steps: Array<[Intl.RelativeTimeFormatUnit, number]> = [
    ['second', 60],
    ['minute', 60],
    ['hour', 24],
    ['day', 30],
    ['month', 12],
  ];

  let value = seconds;
  for (const [unit, size] of steps) {
    if (Math.abs(value) < size) return rtf.format(-value, unit);
    value = Math.round(value / size);
  }
  return rtf.format(-value, 'year');
}

/** Greeting for the dashboard header (context.md §13). */
export function greeting(date = new Date()): string {
  const hour = date.getHours();
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

/**
 * A heading for a day of activity. Inside the last week people think in
 * weekdays — "that was Tuesday" — and beyond it they think in dates, so the
 * label switches at seven days rather than trying to be clever about it.
 */
export function dayGroupLabel(value: string): string {
  const date = parseDbDate(value);
  const now = new Date();
  const dayDiff = Math.round((startOfDay(now) - startOfDay(date)) / 86_400_000);

  if (dayDiff === 0) return 'Today';
  if (dayDiff === 1) return 'Yesterday';
  if (dayDiff > 1 && dayDiff < 7) {
    return new Intl.DateTimeFormat('en-IN', { weekday: 'long' }).format(date);
  }

  const sameYear = date.getFullYear() === now.getFullYear();
  return new Intl.DateTimeFormat('en-IN', {
    day: 'numeric',
    month: 'long',
    ...(sameYear ? {} : { year: 'numeric' }),
  }).format(date);
}

/** Group any dated rows into the day buckets the timeline renders. */
export function groupByDate<T extends { entry_date: string }>(
  rows: T[],
  label: (date: string) => string = friendlyDate,
): Array<{ date: string; label: string; items: T[] }> {
  const buckets = new Map<string, T[]>();
  for (const row of rows) {
    const key = row.entry_date.slice(0, 10);
    const bucket = buckets.get(key);
    if (bucket) bucket.push(row);
    else buckets.set(key, [row]);
  }
  return [...buckets.entries()]
    .sort((a, b) => (a[0] < b[0] ? 1 : -1))
    .map(([date, items]) => ({ date, label: label(date), items }));
}
