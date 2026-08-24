'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Card, EmptyState, ErrorNote, cn } from '@/components/ui/primitives';
import { staggerStyle } from '@/components/motion/reveal';
import { ConfirmDialog } from '@/components/ui/modal';
import { Money } from '@/components/money';
import { TransactionSheet } from '@/components/ledger/transaction-sheet';
import { ConvertedFrom } from '@/components/ledger/conversion';
import { SettleSheet } from '@/components/ledger/settle-sheet';
import { ArrowDownIcon, ArrowUpIcon, SettleIcon, WalletIcon } from '@/components/icons';
import { voidSettlement, voidTransaction } from '@/lib/actions';
import { groupByDate } from '@/lib/dates';
import { formatMinor } from '@/lib/money';
import { entryIsReceivable, entryLabel } from '@/lib/direction';
import type { OpenTransaction, Person, PersonBalance, TimelineEntry } from '@/lib/types';

/**
 * Person timeline (context.md §16).
 *
 * Grouped by day with plain-language headings. Each row says what it is, how
 * much, and where it stands — and nothing more, because a dense ledger becomes
 * unreadable the moment every row grows a toolbar. Actions appear on the
 * selected row only.
 */
export function Timeline({
  entries,
  person,
  balance,
  openTransactions,
  currency,
}: {
  entries: TimelineEntry[];
  person: Person;
  balance: PersonBalance;
  openTransactions: OpenTransaction[];
  currency: string;
}) {
  const router = useRouter();
  const [expanded, setExpanded] = useState<string | null>(null);
  const [editing, setEditing] = useState<TimelineEntry | null>(null);
  const [settlingTxnId, setSettlingTxnId] = useState<string | null>(null);
  const [confirmVoid, setConfirmVoid] = useState<TimelineEntry | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  if (entries.length === 0) {
    return (
      <Card>
        <EmptyState
          icon={<WalletIcon />}
          title="No transactions yet"
          description="Your activity with this account will appear here."
        />
      </Card>
    );
  }

  function doVoid(entry: TimelineEntry) {
    setError(null);
    startTransition(async () => {
      const result =
        entry.entry_kind === 'transaction'
          ? await voidTransaction(person.id, entry.id)
          : await voidSettlement(person.id, entry.id);

      if (!result.ok) {
        setError(result.error);
        return;
      }
      setConfirmVoid(null);
      setExpanded(null);
      router.refresh();
    });
  }

  const groups = groupByDate(entries);

  return (
    <div className="space-y-5">
      {error ? <ErrorNote>{error}</ErrorNote> : null}

      {groups.map((group) => (
        <div key={group.date}>
          <p className="mb-2 flex items-center gap-3 px-1 text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
            {group.label}
            <span aria-hidden className="h-px flex-1 bg-line" />
          </p>

          <Card className="overflow-hidden">
            <ul>
              {group.items.map((entry) => {
                const isSettlement = entry.entry_kind === 'settlement';
                // `money_direction` is the flow of cash; for a transaction the
                // debt runs the other way, which is what the row is about.
                const incoming = entry.money_direction === 'in';
                const receivable = entryIsReceivable(entry.entry_type);
                const open = expanded === entry.id;

                return (
                  <li
                    key={`${entry.entry_kind}-${entry.id}`}
                    className="reveal-row border-b border-line last:border-0"
                    style={staggerStyle(group.items.indexOf(entry))}
                  >
                    <button
                      type="button"
                      onClick={() => setExpanded(open ? null : entry.id)}
                      aria-expanded={open}
                      className={cn(
                        'flex w-full items-center gap-3 px-4 py-3 text-left sm:px-5',
                        'transition-colors duration-[var(--dur)] ease-[var(--ease)]',
                        open ? 'bg-sunken' : 'hover:bg-sunken',
                        entry.is_void && 'opacity-55',
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
                        <span className="flex flex-wrap items-center gap-x-2 gap-y-1">
                          <span className="text-[0.8125rem] font-medium text-ink">
                            {entry.is_opening
                              ? 'Opening balance'
                              : entryLabel(entry.entry_kind, entry.entry_type)}
                          </span>
                          {entry.is_void ? (
                            <StatusChip tone="void">Voided</StatusChip>
                          ) : entry.status === 'settled' ? (
                            <StatusChip tone="done">Settled</StatusChip>
                          ) : entry.status === 'partial' ? (
                            <StatusChip tone="partial">
                              {formatMinor(entry.remaining_minor ?? 0, currency)} left
                            </StatusChip>
                          ) : null}
                        </span>
                        {entry.note ? (
                          <span className="mt-0.5 block truncate text-[0.75rem] text-ink-faint">
                            {entry.note}
                          </span>
                        ) : null}
                        {/* What was actually handed over, when that was not this
                            account's currency. The converted figure is on the
                            right; this is the half that must never be hidden. */}
                        {entry.entered_currency ? (
                          <ConvertedFrom
                            className="mt-0.5 block truncate"
                            enteredMinor={entry.entered_amount_minor}
                            enteredCurrency={entry.entered_currency}
                            rateE9={entry.exchange_rate_e9}
                            accountCurrency={currency}
                            conversionMode={entry.conversion_mode}
                            autoConvertedMinor={entry.auto_converted_amount_minor}
                          />
                        ) : null}
                      </span>

                      <Money
                        minor={entry.amount_minor}
                        currency={currency}
                        tone={isSettlement ? 'neutral' : receivable ? 'receivable' : 'payable'}
                        className={cn(
                          'shrink-0 text-[0.875rem] font-semibold',
                          entry.is_void && 'line-through',
                        )}
                      />
                    </button>

                    {open && !entry.is_void ? (
                      <div className="flex flex-wrap gap-2 border-t border-line bg-sunken px-4 py-3 sm:px-5">
                        {entry.entry_kind === 'transaction' && (entry.remaining_minor ?? 0) > 0 ? (
                          <RowAction onClick={() => setSettlingTxnId(entry.id)}>
                            Settle this
                          </RowAction>
                        ) : null}
                        {entry.entry_kind === 'transaction' ? (
                          <RowAction onClick={() => setEditing(entry)}>Edit</RowAction>
                        ) : null}
                        <RowAction tone="danger" onClick={() => setConfirmVoid(entry)}>
                          {entry.entry_kind === 'transaction' ? 'Void' : 'Reverse'}
                        </RowAction>
                      </div>
                    ) : null}

                    {open && entry.is_void ? (
                      <p className="border-t border-line bg-sunken px-4 py-3 text-[0.75rem] text-ink-faint sm:px-5">
                        This entry was voided. It stays here as history and does not affect any
                        balance.
                      </p>
                    ) : null}
                  </li>
                );
              })}
            </ul>
          </Card>
        </div>
      ))}

      {editing ? (
        <TransactionSheet
          open
          onClose={() => setEditing(null)}
          currency={currency}
          mode="edit"
          person={{
            id: person.id,
            name: person.name,
            currency,
            default_currency: balance.default_currency,
          }}
          transaction={{
            id: editing.id,
            type: editing.entry_type === 'credit' ? 'credit' : 'debit',
            amount_minor: editing.amount_minor,
            transaction_date: editing.entry_date,
            description: editing.note,
            // An edit reopens on what was actually typed, in the currency it
            // was typed in — and on the actual converted amount when the rate
            // was overridden, so re-saving cannot silently restate the row.
            entered_amount_minor: editing.entered_amount_minor,
            entered_currency: editing.entered_currency,
            conversion_mode: editing.conversion_mode,
            auto_converted_amount_minor: editing.auto_converted_amount_minor,
          }}
        />
      ) : null}

      {settlingTxnId ? (
        <SettleSheet
          open
          onClose={() => setSettlingTxnId(null)}
          balance={balance}
          openTransactions={openTransactions}
          currency={currency}
          presetTransactionId={settlingTxnId}
        />
      ) : null}

      <ConfirmDialog
        open={confirmVoid !== null}
        onClose={() => setConfirmVoid(null)}
        onConfirm={() => confirmVoid && doVoid(confirmVoid)}
        pending={pending}
        title={
          confirmVoid?.entry_kind === 'settlement' ? 'Reverse this settlement?' : 'Void this transaction?'
        }
        confirmLabel={confirmVoid?.entry_kind === 'settlement' ? 'Reverse' : 'Void'}
        body={
          confirmVoid?.entry_kind === 'settlement' ? (
            <>
              The {formatMinor(confirmVoid.amount_minor, currency)} goes back to outstanding. The
              record stays in the timeline marked as reversed.
            </>
          ) : (
            <>
              The transaction stays in the timeline as history but stops counting towards any
              balance. If it has already been settled, void those settlements first.
            </>
          )
        }
      />
    </div>
  );
}

function StatusChip({
  children,
  tone,
}: {
  children: React.ReactNode;
  tone: 'done' | 'partial' | 'void';
}) {
  return (
    <span
      className={cn(
        'rounded-full border px-2 py-0.5 text-[0.6875rem] font-medium',
        tone === 'done' && 'border-receivable-line bg-receivable-soft text-receivable',
        tone === 'partial' && 'border-accent-line bg-accent-soft text-accent',
        tone === 'void' && 'border-line bg-sunken text-ink-faint',
      )}
    >
      {children}
    </span>
  );
}

function RowAction({
  children,
  onClick,
  tone = 'default',
}: {
  children: React.ReactNode;
  onClick: () => void;
  tone?: 'default' | 'danger';
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'rounded-field border bg-surface px-3 py-1.5 text-[0.8125rem] font-medium',
        'transition-[border-color,background-color,color] duration-[var(--dur)] ease-[var(--ease)]',
        tone === 'danger'
          ? 'border-payable-line text-payable hover:bg-payable-soft'
          : 'border-line-strong text-ink hover:bg-sunken',
      )}
    >
      {children}
    </button>
  );
}
