import { balanceTone, formatApprox, formatMoney } from '@/lib/money';
import { cn } from '@/components/ui/primitives';

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
