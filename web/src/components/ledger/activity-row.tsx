import Link from 'next/link';
import { Money } from '@/components/money';
import { cn } from '@/components/ui/primitives';
import { ArrowDownIcon, ArrowUpIcon, SettleIcon } from '@/components/icons';
import { friendlyDate } from '@/lib/dates';
import { entryIsReceivable, entryLabel } from '@/lib/direction';
import type { ActivityItem } from '@/lib/types';

/**
 * One line of the financial timeline, shared by the dashboard and the activity
 * page so the two can never drift apart.
 *
 * Three things distinguish the kinds of entry at a glance and they all agree
 * with each other: the glyph (down / up / settle), the tint behind it, and the
 * colour of the amount. Settlement is deliberately neutral — money moving to
 * close a debt is not new money in either direction.
 */
export function ActivityRow({
  item,
  currency,
  showDate = false,
}: {
  item: ActivityItem;
  currency: string;
  showDate?: boolean;
}) {
  const isSettlement = item.entry_kind === 'settlement';
  // "Receivable", not "incoming": what the row is coloured by is which way the
  // debt runs, which is the question the reader is actually asking.
  const receivable = entryIsReceivable(item.entry_type);
  const kind = entryLabel(item.entry_kind, item.entry_type);

  const meta = [item.note, showDate ? friendlyDate(item.entry_date) : null]
    .filter(Boolean)
    .join(' · ');

  return (
    <Link
      href={`/people/${item.person_id}`}
      className={cn(
        'flex items-center gap-3 px-4 py-3 sm:px-5',
        'transition-colors duration-[var(--dur)] ease-[var(--ease)] hover:bg-sunken',
      )}
    >
      <span
        className={cn(
          'grid size-9 shrink-0 place-items-center rounded-[0.625rem] border',
          isSettlement
            ? 'border-line bg-sunken text-ink-muted'
            : receivable
              ? 'border-receivable-line bg-receivable-soft text-receivable'
              : 'border-payable-line bg-payable-soft text-payable',
        )}
      >
        {isSettlement ? (
          <SettleIcon className="size-4" />
        ) : receivable ? (
          <ArrowUpIcon className="size-4" />
        ) : (
          <ArrowDownIcon className="size-4" />
        )}
      </span>

      <span className="min-w-0 flex-1">
        <span className="block truncate text-[0.8125rem] font-medium text-ink">
          {item.person_name}
        </span>
        <span className="block truncate text-[0.75rem] text-ink-faint">
          {meta ? `${kind} · ${meta}` : kind}
        </span>
      </span>

      <Money
        minor={item.amount_minor}
        currency={currency}
        tone={isSettlement ? 'neutral' : receivable ? 'receivable' : 'payable'}
        className="shrink-0 text-[0.875rem] font-semibold"
      />
    </Link>
  );
}
