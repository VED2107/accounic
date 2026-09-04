'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Card, EmptyState, ErrorNote, cn } from '@/components/ui/primitives';
import { staggerStyle } from '@/components/motion/reveal';
import { ConfirmDialog } from '@/components/ui/modal';
import { Money } from '@/components/money';
import { TransactionSheet } from '@/components/ledger/transaction-sheet';
import { RateNote } from '@/components/ledger/conversion';
import { SettleSheet } from '@/components/ledger/settle-sheet';
import {
  ArrowDownIcon,
  ArrowRightIcon,
  ArrowUpIcon,
  SettleIcon,
  WalletIcon,
} from '@/components/icons';
import { voidSettlement, voidTransaction, voidTransfer } from '@/lib/actions';
import { transferLabel } from '@/lib/transfers';
import { groupByDate } from '@/lib/dates';
import { formatApprox, formatMoney } from '@/lib/money';
import { entryIsReceivable, entryLabel } from '@/lib/direction';
import { normaliseCode } from '@/lib/currencies';
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
      // A transfer leg is never retracted on its own: the whole transfer is,
      // and the other person's entry goes with it. The database refuses any
      // other arrangement, so this is the only call that can succeed.
      const result = entry.transfer_id
        ? await voidTransfer(entry.transfer_id, 'Retracted from the person page')
        : entry.entry_kind === 'transaction'
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
                // A transfer leg is stored as an ordinary debit or credit, and
                // "Debit" is exactly the wrong word for it: the user moved
                // their own money between two accounts rather than lending
                // anything. The label says where it went (lib/transfers.ts).
                const isTransfer = Boolean(entry.transfer_id);
                // `money_direction` is the flow of cash; for a transaction the
                // debt runs the other way, which is what the row is about — so
                // the row reads the DEBT direction, and the cash direction is
                // only consulted where a settlement is being described.
                const receivable = entryIsReceivable(entry.entry_type);
                const open = expanded === entry.id;

                // What was entered, falling back to the ledger figure against a
                // database older than 0018 — where, for a same-currency entry,
                // they are the same number anyway.
                const entryMinor = entry.entry_amount_minor ?? entry.amount_minor;
                const entryCurrency = normaliseCode(entry.entry_currency) || currency;
                const baseCurrency = normaliseCode(entry.base_currency);

                // One equivalent, chosen so it always says something the
                // headline does not: the ledger figure when this entry was
                // converted into the account, otherwise the workspace figure.
                const equivalent =
                  entryCurrency !== currency
                    ? { minor: entry.amount_minor, currency }
                    : baseCurrency && baseCurrency !== currency && entry.amount_base_minor != null
                      ? { minor: entry.amount_base_minor, currency: baseCurrency }
                      : null;

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
                        'press flex w-full items-center gap-3 px-4 py-3 text-left sm:px-5',
                        'transition-[background-color,opacity,transform] duration-[var(--dur-fast)] ease-[var(--ease)]',
                        open ? 'bg-sunken' : 'hover:bg-sunken',
                        entry.is_void && 'opacity-55',
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
                        {isTransfer ? (
                          <ArrowRightIcon
                            className={cn(
                              'size-4',
                              entry.transfer_role === 'source' && 'rotate-180',
                            )}
                          />
                        ) : isSettlement ? (
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
                            {isTransfer
                              ? transferLabel(
                                  entry.transfer_role,
                                  entry.transfer_counterparty_name,
                                )
                              : entry.is_opening
                                ? 'Opening balance'
                                : entryLabel(entry.entry_kind, entry.entry_type)}
                          </span>
                          {/* So the two halves can be recognised as one thing
                              from either account. */}
                          {isTransfer ? <StatusChip tone="transfer">Transfer</StatusChip> : null}
                          {entry.is_void ? (
                            <StatusChip tone="void">Voided</StatusChip>
                          ) : isTransfer ? null : entry.status === 'settled' ? (
                            <StatusChip tone="done">Settled</StatusChip>
                          ) : entry.status === 'partial' ? (
                            <StatusChip tone="partial">
                              {formatMoney(entry.remaining_minor ?? 0, currency, { base: currency })} left
                            </StatusChip>
                          ) : null}
                        </span>
                        {entry.note ? (
                          <span className="mt-0.5 block truncate text-[0.75rem] text-ink-faint">
                            {entry.note}
                          </span>
                        ) : null}
                        {/* The rate that links the two figures on the right, and
                            whether a human chose either of them. Third and
                            quietest: it must not compete with the amount. */}
                        <RateNote
                          className="mt-0.5 block truncate"
                          enteredMinor={entry.entered_amount_minor}
                          enteredCurrency={entry.entered_currency}
                          rateE9={entry.exchange_rate_e9}
                          rateSource={entry.exchange_rate_source}
                          accountCurrency={currency}
                          conversionMode={entry.conversion_mode}
                          autoConvertedMinor={entry.auto_converted_amount_minor}
                        />
                      </span>

                      {/* The amount that was ENTERED leads, in the currency it
                          was entered in — a dirham entry is 400 AED and says so.
                          Under it, the one equivalent that adds something: the
                          ledger figure when the entry was converted into this
                          account, otherwise the workspace-currency figure for an
                          account kept in a foreign currency. Never both, and
                          never the equivalent alone (upgrade §44). */}
                      <span className="flex shrink-0 flex-col items-end">
                        <Money
                          minor={entryMinor}
                          currency={entryCurrency}
                          base={currency}
                          tone={isSettlement ? 'neutral' : receivable ? 'receivable' : 'payable'}
                          className={cn(
                            'text-[0.875rem] font-semibold',
                            entry.is_void && 'line-through',
                          )}
                        />
                        {equivalent ? (
                          <span
                            className={cn(
                              'tnum text-[0.75rem] text-ink-faint',
                              entry.is_void && 'line-through',
                            )}
                          >
                            {formatApprox(equivalent.minor, equivalent.currency)}
                          </span>
                        ) : null}
                      </span>
                    </button>

                    {open && !entry.is_void ? (
                      <div className="flex flex-wrap gap-2 border-t border-line bg-sunken px-4 py-3 sm:px-5">
                        {/* A transfer offers neither: it is not settled by
                            anybody, and it is never edited one side at a time.
                            Both restrictions are enforced in the database as
                            well — this is the affordance agreeing with it. */}
                        {!isTransfer &&
                        entry.entry_kind === 'transaction' &&
                        (entry.remaining_minor ?? 0) > 0 ? (
                          <RowAction onClick={() => setSettlingTxnId(entry.id)}>
                            Settle this
                          </RowAction>
                        ) : null}
                        {!isTransfer && entry.entry_kind === 'transaction' ? (
                          <RowAction onClick={() => setEditing(entry)}>Edit</RowAction>
                        ) : null}
                        <RowAction tone="danger" onClick={() => setConfirmVoid(entry)}>
                          {isTransfer
                            ? 'Retract transfer'
                            : entry.entry_kind === 'transaction'
                              ? 'Void'
                              : 'Reverse'}
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
            // And on the rate it was written at, so a row rated by hand is not
            // quietly restated at today's rate by an unrelated edit.
            exchange_rate_e9: editing.exchange_rate_e9,
            exchange_rate_source: editing.exchange_rate_source,
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
          confirmVoid?.transfer_id
            ? 'Retract this transfer?'
            : confirmVoid?.entry_kind === 'settlement'
              ? 'Reverse this settlement?'
              : 'Void this transaction?'
        }
        confirmLabel={
          confirmVoid?.transfer_id
            ? 'Retract transfer'
            : confirmVoid?.entry_kind === 'settlement'
              ? 'Reverse'
              : 'Void'
        }
        body={
          confirmVoid?.transfer_id ? (
            <>
              <p>
                Both sides are retracted together.{' '}
                {formatMoney(confirmVoid.amount_minor, currency, { base: currency })} returns to this account, and
                the matching entry on{' '}
                {confirmVoid.transfer_counterparty_name ?? 'the other account'} is retracted
                with it.
              </p>
              <p className="mt-2 text-ink-faint">
                Nothing is deleted. Both entries stay on both timelines, marked retracted, with
                their amounts and rate exactly as they were.
              </p>
            </>
          ) : confirmVoid?.entry_kind === 'settlement' ? (
            <>
              The {formatMoney(confirmVoid.amount_minor, currency, { base: currency })} goes back to outstanding. The
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
  tone: 'done' | 'partial' | 'void' | 'transfer';
}) {
  return (
    <span
      className={cn(
        'rounded-full border px-2 py-0.5 text-[0.6875rem] font-medium',
        tone === 'done' && 'border-receivable-line bg-receivable-soft text-receivable',
        tone === 'partial' && 'border-accent-line bg-accent-soft text-accent',
        tone === 'void' && 'border-line bg-sunken text-ink-faint',
        tone === 'transfer' && 'border-line-strong bg-sunken text-ink-muted',
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
