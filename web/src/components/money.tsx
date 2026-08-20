import { balanceTone, formatMinor } from '@/lib/money';
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
}: {
  minor: number;
  currency?: string;
  tone?: MoneyTone;
  className?: string;
  signed?: boolean;
  compact?: boolean;
}) {
  const resolved = resolveTone(tone, minor);
  const text = formatMinor(tone === 'auto' ? Math.abs(minor) : minor, currency, {
    signed,
    compactDecimals: compact,
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
      <p className="text-[0.8125rem] font-medium text-ink-muted">{label}</p>
      <p className="mt-1 truncate font-display text-[1.75rem] font-semibold leading-tight tracking-tight">
        <Money minor={minor} currency={currency} tone={tone} />
      </p>
      {sublabel ? <p className="mt-0.5 text-[0.8125rem] text-ink-faint">{sublabel}</p> : null}
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
  className,
}: {
  netMinor: number;
  currency?: string;
  className?: string;
}) {
  const tone = balanceTone(netMinor);
  return (
    <span className={cn('flex shrink-0 flex-col items-end leading-tight', className)}>
      <span
        className={cn(
          'tnum font-display text-[0.9375rem] font-semibold tracking-tight',
          tone === 'receivable' && 'text-receivable',
          tone === 'payable' && 'text-payable',
          tone === 'settled' && 'text-ink-faint',
        )}
      >
        {tone === 'settled' ? 'Settled' : formatMinor(Math.abs(netMinor), currency)}
      </span>
      {tone === 'settled' ? (
        <span className="text-[0.6875rem] text-ink-faint">up</span>
      ) : (
        <span
          className={cn(
            'text-[0.6875rem] font-medium',
            tone === 'receivable' ? 'text-receivable/75' : 'text-payable/75',
          )}
        >
          {tone}
        </span>
      )}
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
