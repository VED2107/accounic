import Link from 'next/link';
import { Money } from '@/components/money';
import { cn } from '@/components/ui/primitives';
import { ArrowDownIcon, ArrowUpIcon, SettleIcon } from '@/components/icons';
import { friendlyDate } from '@/lib/dates';
import { entryIsReceivable, entryLabel } from '@/lib/direction';
import { ConvertedFrom } from '@/components/ledger/conversion';
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
  const kind = item.is_opening ? 'Opening balance' : entryLabel(item.entry_kind, item.entry_type);

  // Each row carries its own currency, because a workspace-wide feed is exactly
  // where two of them sit next to each other (upgrade §9).
  const rowCurrency = item.currency ?? currency;

  const when = showDate ? friendlyDate(item.entry_date) : null;

  // An opening balance is stored with "Opening balance" as its note, so the
  // row printed the phrase twice — once as the kind and once as the note. A
  // note that only repeats the label is not a note.
  const note = item.note?.trim();
  const showNote = Boolean(note) && note !== kind;

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
          'grid size-9 shrink-0 place-items-center rounded-field border',
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
        <span className="block truncate text-[0.875rem] font-medium text-ink">
          {item.person_name}
        </span>

        {/* Three levels, not one run-on line: what kind of entry this is, then
            when, then the note. Rows used to read as one undifferentiated grey
            string, which is why a feed of them was hard to scan (§15). */}
        <span className="flex min-w-0 items-center gap-1.5 text-[0.75rem]">
          <span
            className={cn(
              'shrink-0 font-medium',
              isSettlement
                ? 'text-ink-muted'
                : receivable
                  ? 'text-receivable/90'
                  : 'text-payable/90',
            )}
          >
            {kind}
          </span>
          {when ? (
            <>
              <span className="text-ink-subtle">·</span>
              <span className="shrink-0 text-ink-faint">{when}</span>
            </>
          ) : null}
          {showNote ? (
            <>
              <span className="text-ink-subtle">·</span>
              <span className="truncate text-ink-faint">{note}</span>
            </>
          ) : null}
        </span>
        {/* What was actually handed over, when that was not this account's
            currency — and whether the figure beside it was the rate's or the
            user's (upgrade §40). */}
        {item.entered_currency ? (
          <ConvertedFrom
            className="block truncate"
            enteredMinor={item.entered_amount_minor}
            enteredCurrency={item.entered_currency}
            rateE9={item.exchange_rate_e9}
            accountCurrency={rowCurrency}
            conversionMode={item.conversion_mode}
            autoConvertedMinor={item.auto_converted_amount_minor}
          />
        ) : null}
      </span>

      <Money
        minor={item.amount_minor}
        currency={rowCurrency}
        tone={isSettlement ? 'neutral' : receivable ? 'receivable' : 'payable'}
        className="money shrink-0"
      />
    </Link>
  );
}
