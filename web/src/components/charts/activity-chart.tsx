'use client';

import { useCallback, useLayoutEffect, useRef, useState } from 'react';
import type { ActivityBucket } from '@/lib/queries';
import { formatMinor } from '@/lib/money';
import { cn } from '@/components/ui/primitives';

/**
 * Thirty days of flow, with the day under the pointer named (upgrade §8).
 *
 * The sparkline beside the net position says what the shape is; this says what
 * happened. Each day is a column above and below a baseline — received above in
 * green, given below in red — because money in and money out are opposite
 * directions and drawing them as two stacked positives makes the reader do the
 * subtraction themselves.
 *
 * Settled has no column. It is not a flow between the two of you, it is one of
 * those flows being closed, so drawing it as a third bar would double-count the
 * same money on the same day. It is in the readout instead, where it belongs.
 *
 * Interaction is pointer-agnostic: a mouse hovers, a finger drags, both land on
 * the nearest column. Nothing depends on hover alone. The chart is still worth
 * reading with no interaction at all, which is why the totals sit above it
 * rather than only inside the tooltip.
 */
export function ActivityChart({
  buckets,
  currency,
  className,
}: {
  /** As the RPC returns them — any order; sorted here. */
  buckets: ActivityBucket[];
  currency: string;
  className?: string;
}) {
  const days = [...buckets].sort((a, b) => (a.bucket < b.bucket ? -1 : 1));

  const [active, setActive] = useState<number | null>(null);
  const plotRef = useRef<HTMLDivElement>(null);
  const tipRef = useRef<HTMLDivElement>(null);
  const [tipLeft, setTipLeft] = useState(0);

  const pick = useCallback(
    (clientX: number) => {
      const plot = plotRef.current;
      if (!plot || days.length === 0) return;
      const box = plot.getBoundingClientRect();
      const ratio = (clientX - box.left) / box.width;
      const index = Math.round(ratio * (days.length - 1));
      setActive(Math.min(days.length - 1, Math.max(0, index)));
    },
    [days.length],
  );

  // Clamping happens after the tooltip has been measured, so a day at either
  // end of the window gets a tooltip that stays inside the card rather than one
  // that is cut off by the card's own overflow.
  useLayoutEffect(() => {
    if (active === null) return;
    const plot = plotRef.current;
    const tip = tipRef.current;
    if (!plot || !tip) return;

    const width = plot.clientWidth;
    const tipWidth = tip.offsetWidth;
    const centre = days.length < 2 ? width / 2 : (active / (days.length - 1)) * width;
    const margin = 8;
    setTipLeft(
      Math.min(Math.max(centre - tipWidth / 2, margin), Math.max(margin, width - tipWidth - margin)),
    );
  }, [active, days.length]);

  if (days.length < 2) return null;

  const peak = Math.max(
    1,
    ...days.map((day) => Math.max(day.credit, day.debit)),
  );

  const totals = days.reduce(
    (sum, day) => ({
      credit: sum.credit + day.credit,
      debit: sum.debit + day.debit,
      settled: sum.settled + day.settled,
    }),
    { credit: 0, debit: 0, settled: 0 },
  );

  const shown = active === null ? null : days[active]!;

  return (
    <div className={cn('select-none', className)}>
      {/* Legend and window totals. The chart means something before it is
          touched, which is the test of whether the tooltip is a convenience or
          a load-bearing part of the design. */}
      <div className="mb-4 flex flex-wrap items-baseline gap-x-5 gap-y-1.5">
        <LegendItem tone="receivable" label="You received" value={formatMinor(totals.credit, currency)} />
        <LegendItem tone="payable" label="You gave" value={formatMinor(totals.debit, currency)} />
        <LegendItem tone="neutral" label="Settled" value={formatMinor(totals.settled, currency)} />
      </div>

      <div className="relative">
        {shown ? (
          <div
            ref={tipRef}
            role="status"
            style={{ left: tipLeft }}
            className={cn(
              'pointer-events-none absolute bottom-full z-10 mb-2 w-max min-w-44 max-w-full',
              'rounded-field border border-line-strong bg-raised px-3 py-2.5 shadow-[var(--shadow-pop)]',
              'animate-[fade_var(--dur-fast)_ease-out_both]',
            )}
          >
            <p className="text-[0.75rem] font-semibold text-ink">{dayLabel(shown.bucket)}</p>
            <dl className="mt-1.5 space-y-1">
              <TipRow tone="receivable" label="You received" value={formatMinor(shown.credit, currency)} />
              <TipRow tone="payable" label="You gave" value={formatMinor(shown.debit, currency)} />
              <TipRow tone="neutral" label="Settled" value={formatMinor(shown.settled, currency)} />
            </dl>
          </div>
        ) : null}

        <div
          ref={plotRef}
          // `touch-action: pan-y` so dragging across the chart reads a day
          // without stealing the page's vertical scroll.
          className="relative h-28 touch-pan-y"
          onPointerMove={(event) => pick(event.clientX)}
          onPointerDown={(event) => pick(event.clientX)}
          onPointerLeave={() => setActive(null)}
          onPointerCancel={() => setActive(null)}
        >
          <div className="flex h-full items-stretch gap-px">
            {days.map((day, index) => (
              <Column
                key={day.bucket}
                credit={day.credit}
                debit={day.debit}
                peak={peak}
                active={index === active}
              />
            ))}
          </div>

          {/* The zero line. Half of the plot is above it and half below, so the
              two directions are comparable at a glance. */}
          <div
            aria-hidden
            className="pointer-events-none absolute inset-x-0 top-1/2 h-px -translate-y-1/2 bg-line-strong"
          />
        </div>
      </div>

      <div className="mt-2 flex justify-between text-[0.6875rem] text-ink-faint">
        <span>{dayLabel(days[0]!.bucket)}</span>
        <span>{dayLabel(days[days.length - 1]!.bucket)}</span>
      </div>
    </div>
  );
}

/** One day: received above the line, given below it. */
function Column({
  credit,
  debit,
  peak,
  active,
}: {
  credit: number;
  debit: number;
  peak: number;
  active: boolean;
}) {
  // A day with a real but tiny amount still gets a visible mark: a column that
  // rounds to nothing reads as a day when nothing happened, which is a
  // different fact.
  const up = credit === 0 ? 0 : Math.max(2, (credit / peak) * 100);
  const down = debit === 0 ? 0 : Math.max(2, (debit / peak) * 100);

  return (
    <div
      className={cn(
        'relative flex min-w-0 flex-1 flex-col rounded-[2px]',
        'transition-colors duration-[var(--dur-fast)]',
        active && 'bg-accent-soft',
      )}
    >
      <div className="flex flex-1 items-end justify-center">
        <span
          style={{ height: `${up}%` }}
          className={cn(
            'w-full rounded-t-[2px] bg-receivable',
            'transition-opacity duration-[var(--dur-fast)]',
            active ? 'opacity-100' : 'opacity-80',
          )}
        />
      </div>
      <div className="flex flex-1 items-start justify-center">
        <span
          style={{ height: `${down}%` }}
          className={cn(
            'w-full rounded-b-[2px] bg-payable',
            'transition-opacity duration-[var(--dur-fast)]',
            active ? 'opacity-100' : 'opacity-80',
          )}
        />
      </div>
    </div>
  );
}

function LegendItem({
  tone,
  label,
  value,
}: {
  tone: 'receivable' | 'payable' | 'neutral';
  label: string;
  value: string;
}) {
  return (
    <span className="flex items-baseline gap-2">
      <span
        aria-hidden
        className={cn(
          'size-2 shrink-0 translate-y-[-1px] rounded-[2px]',
          tone === 'receivable' && 'bg-receivable',
          tone === 'payable' && 'bg-payable',
          tone === 'neutral' && 'bg-money-neutral',
        )}
      />
      <span className="text-[0.75rem] text-ink-muted">{label}</span>
      <span className="money-sm tnum text-ink">{value}</span>
    </span>
  );
}

function TipRow({
  tone,
  label,
  value,
}: {
  tone: 'receivable' | 'payable' | 'neutral';
  label: string;
  value: string;
}) {
  return (
    <div className="flex items-baseline justify-between gap-6">
      <dt className="flex items-baseline gap-1.5 text-[0.75rem] text-ink-muted">
        <span
          aria-hidden
          className={cn(
            'size-1.5 shrink-0 rounded-full',
            tone === 'receivable' && 'bg-receivable',
            tone === 'payable' && 'bg-payable',
            tone === 'neutral' && 'bg-money-neutral',
          )}
        />
        {label}
      </dt>
      <dd
        className={cn(
          'money-sm tnum',
          tone === 'receivable' && 'text-receivable',
          tone === 'payable' && 'text-payable',
          tone === 'neutral' && 'text-ink-muted',
        )}
      >
        {value}
      </dd>
    </div>
  );
}

/** "24 Aug" — the axis and the tooltip agree on how a day is written. */
function dayLabel(bucket: string): string {
  const date = new Date(`${bucket.slice(0, 10)}T00:00:00`);
  if (Number.isNaN(date.getTime())) return bucket;
  return date.toLocaleDateString(undefined, { day: 'numeric', month: 'short' });
}
