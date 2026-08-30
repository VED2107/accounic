import { balanceTone, formatApprox, formatMoney } from '@/lib/money';
import { cn } from '@/components/ui/primitives';
import { orderCurrencyRows } from '@/lib/currency-breakdown';
import type { CurrencyHalfBreakdown } from '@/lib/types';

/**
 * Money rendering (context.md §8, §18).
 *
 * Colour is reserved for direction and nothing else, so a glance answers "is
 * this coming to me or leaving me" without reading a word. Every amount is
 * tabular-figure so columns of numbers line up.
 */

export type MoneyTone = 'receivable' | 'payable' | 'neutral' | 'auto';

const TONE_CLASS: Record<Exclude<MoneyTone, 'auto'>, string> = {
  receivable: 'text-receivable',
  payable: 'text-payable',
  neutral: 'text-ink',
};

function resolveTone(tone: MoneyTone, minor: number): Exclude<MoneyTone, 'auto'> {
  if (tone !== 'auto') return tone;
  const resolved = balanceTone(minor);
  return resolved === 'receivable' ? 'receivable' : resolved === 'payable' ? 'payable' : 'neutral';
}

export function Money({
  minor,
  currency = 'INR',
  tone = 'neutral',
  className,
  signed = false,
  compact = true,
  withCode = true,
}: {
  minor: number;
  currency?: string;
  tone?: MoneyTone;
  className?: string;
  signed?: boolean;
  compact?: boolean;
  /**
   * The ISO code after the figure — `$40 USD`, not `$40` (upgrade §44).
   *
   * On by default, and off only where the code is already stated beside the
   * figure. A symbol alone is ambiguous: `$` is eight of the currencies in this
   * list and `₹` is two, and a ledger that mixes currencies is exactly where
   * that ambiguity costs someone money.
   */
  withCode?: boolean;
}) {
  const resolved = resolveTone(tone, minor);
  const text = formatMoney(tone === 'auto' ? Math.abs(minor) : minor, currency, {
    signed,
    compactDecimals: compact,
    withCode,
  });

  return <span className={cn('tnum', TONE_CLASS[resolved], className)}>{text}</span>;
}

/**
 * A headline figure with its label above it. Large and quiet — big enough to be
 * the first thing read, not so big it turns a financial screen into a poster.
 */
export function MoneyStat({
  label,
  minor,
  currency = 'INR',
  tone = 'neutral',
  sublabel,
  className,
}: {
  label: string;
  minor: number;
  currency?: string;
  tone?: MoneyTone;
  sublabel?: string;
  className?: string;
}) {
  return (
    <div className={cn('min-w-0', className)}>
      <p className="stat-label">{label}</p>
      <p className="money-lg mt-1.5">
        <Money minor={minor} currency={currency} tone={tone} />
      </p>
      {sublabel ? <p className="stat-note mt-1">{sublabel}</p> : null}
    </div>
  );
}

/**
 * The balance at the end of a list row — the visual anchor of that row
 * (context.md §5). Amount first, then the one word that says which way it runs,
 * so the eye reads down a column of figures and only drops to the label when it
 * needs to.
 */
export function NetBadge({
  netMinor,
  currency = 'INR',
  approxMinor,
  approxCurrency,
  className,
}: {
  netMinor: number;
  currency?: string;
  /**
   * The same position in the workspace's own currency, when this row is kept in
   * a different one. A dirham balance in a rupee workspace is two facts, and a
   * row that shows only one of them makes the user do the conversion in their
   * head (upgrade §42).
   */
  approxMinor?: number | null;
  approxCurrency?: string;
  className?: string;
}) {
  const tone = balanceTone(netMinor);
  const showApprox =
    approxMinor != null &&
    approxCurrency != null &&
    approxCurrency !== currency &&
    tone !== 'settled';

  return (
    <span className={cn('flex shrink-0 flex-col items-end gap-0.5 leading-tight', className)}>
      <span
        className={cn(
          'money',
          tone === 'receivable' && 'text-receivable',
          tone === 'payable' && 'text-payable',
          tone === 'settled' && 'text-ink-muted',
        )}
      >
        {tone === 'settled' ? 'Settled' : formatMoney(Math.abs(netMinor), currency)}
      </span>

      {showApprox ? (
        <span className="tnum text-[0.75rem] text-ink-faint">
          {formatApprox(Math.abs(approxMinor), approxCurrency)}
        </span>
      ) : null}

      {/* The state in a word, and in a shape. Colour alone never carries it:
          the pill's tint, its border and the word all say the same thing, so it
          survives a colour-blind reader and a bad monitor alike (§29). */}
      <span
        className={cn(
          'rounded-full border px-1.5 py-px text-[0.6875rem] font-medium',
          tone === 'receivable' && 'border-receivable-line bg-receivable-soft text-receivable',
          tone === 'payable' && 'border-payable-line bg-payable-soft text-payable',
          tone === 'settled' && 'border-line bg-sunken text-ink-muted',
        )}
      >
        {tone === 'settled' ? 'up to date' : tone}
      </span>
    </span>
  );
}

/**
 * A hairline showing how a total splits between the two directions. Not a
 * chart — a proportion, read in the same glance as the numbers above it. Drawn
 * only when both sides are non-zero, because a full-width bar of one colour
 * says nothing the figure has not already said.
 */
export function SplitBar({
  receivable,
  payable,
  className,
}: {
  receivable: number;
  payable: number;
  className?: string;
}) {
  const total = receivable + payable;
  if (total <= 0 || receivable === 0 || payable === 0) return null;
  const share = Math.round((receivable / total) * 100);

  return (
    <div
      className={cn('flex h-1 overflow-hidden rounded-full bg-sunken', className)}
      role="img"
      aria-label={`${share}% receivable, ${100 - share}% payable`}
    >
      <span className="bg-receivable" style={{ width: `${share}%` }} />
      <span className="flex-1 bg-payable" />
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Per-currency breakdown (db/migrations/0024)                                 */
/* -------------------------------------------------------------------------- */

/**
 * Cash in hand / the opening balance, shown in the currency the money was
 * actually entered in — aggregated across every account, one block per
 * currency (db/migrations/0024).
 *
 * The rule this component exists to hold: the large figure is always the
 * ORIGINAL entered amount in its own currency. The workspace-currency
 * equivalent is a small "≈" line beneath it and nothing settles against it.
 * Nothing here reconverts an INR total back into a foreign currency.
 */
export function CurrencyBreakdown({
  rows,
  baseCurrency,
  kind,
  className,
}: {
  rows: CurrencyHalfBreakdown[];
  baseCurrency: string;
  /** 'cash' labels the net figure "Net"; 'opening' labels it "Remaining". */
  kind: 'cash' | 'opening';
  className?: string;
}) {
  const ordered = orderCurrencyRows(rows, baseCurrency);
  if (ordered.length === 0) return null;

  return (
    <div className={cn('divide-y divide-line', className)}>
      {ordered.map((row) => (
        <CurrencyBlock key={`${kind}-${row.currency}`} row={row} baseCurrency={baseCurrency} kind={kind} />
      ))}
    </div>
  );
}

function CurrencyBlock({
  row,
  baseCurrency,
  kind,
}: {
  row: CurrencyHalfBreakdown;
  baseCurrency: string;
  kind: 'cash' | 'opening';
}) {
  const tone = balanceTone(row.net);
  const showApprox = row.currency !== baseCurrency;

  return (
    <div className="px-4 py-4 sm:px-5">
      <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
        <div className="min-w-0">
          <p className="text-[0.6875rem] font-semibold uppercase tracking-wide text-ink-faint">
            {row.currency}
          </p>
          <p
            className={cn(
              'tnum mt-1 text-[1.375rem] font-semibold leading-none',
              tone === 'receivable' && 'text-receivable',
              tone === 'payable' && 'text-payable',
              tone === 'settled' && 'text-ink-muted',
            )}
          >
            {formatMoney(Math.abs(row.net), row.currency)}
          </p>
          {showApprox ? (
            <p className="tnum mt-1 text-[0.75rem] text-ink-faint">
              {row.net_base_minor === null
                ? `no ${row.currency} → ${baseCurrency} rate yet`
                : `≈ ${formatApprox(Math.abs(row.net_base_minor), baseCurrency)}`}
            </p>
          ) : null}
        </div>
        {typeof row.people_count === 'number' && row.people_count > 0 ? (
          <p className="text-[0.6875rem] text-ink-faint">
            {row.entry_count} {row.entry_count === 1 ? 'entry' : 'entries'} ·{' '}
            {row.people_count} {row.people_count === 1 ? 'account' : 'accounts'}
          </p>
        ) : (
          <p className="text-[0.6875rem] text-ink-faint">
            {row.entry_count} {row.entry_count === 1 ? 'entry' : 'entries'}
          </p>
        )}
      </div>

      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 sm:grid-cols-4">
        <BreakdownFigure label="Receivable" minor={row.receivable} currency={row.currency} tone="receivable" />
        <BreakdownFigure label="Payable" minor={row.payable} currency={row.currency} tone="payable" />
        <BreakdownFigure label="Settled" minor={row.settled} currency={row.currency} />
        {row.today !== 0 ? (
          <BreakdownFigure label="Today" minor={row.today} currency={row.currency} />
        ) : (
          <BreakdownFigure
            label={kind === 'opening' ? 'Remaining' : 'Net'}
            minor={Math.abs(row.net)}
            currency={row.currency}
          />
        )}
      </dl>
    </div>
  );
}

function BreakdownFigure({
  label,
  minor,
  currency,
  tone,
}: {
  label: string;
  minor: number;
  currency: string;
  tone?: 'receivable' | 'payable';
}) {
  return (
    <div className="min-w-0">
      <dt className="truncate text-[0.6875rem] text-ink-faint">{label}</dt>
      <dd
        className={cn(
          'tnum truncate text-[0.875rem] font-medium',
          tone === 'receivable' && 'text-receivable',
          tone === 'payable' && 'text-payable',
          !tone && 'text-ink-muted',
        )}
      >
        {formatMoney(minor, currency)}
      </dd>
    </div>
  );
}
