'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Button, ErrorNote } from '@/components/ui/primitives';
import { ConfirmDialog } from '@/components/ui/modal';
import { ArchiveIcon, ArrowDownIcon, ArrowUpIcon, EditIcon, SettleIcon } from '@/components/icons';
import { TransactionSheet } from '@/components/ledger/transaction-sheet';
import { SettleSheet } from '@/components/ledger/settle-sheet';
import { PersonForm } from '@/components/ledger/person-form';
import { deletePerson, setPersonArchived, voidPersonHistory } from '@/lib/actions';
import type { OpenTransaction, Person, PersonBalance, TxnType } from '@/lib/types';
import { TYPE_FOR_FLOW } from '@/lib/direction';

/**
 * Actions on a person account (context.md §9, §17).
 *
 * Settle is the prominent one whenever anything is outstanding — that is the
 * spec's headline interaction. Archiving is offered before deletion, and
 * deletion is only possible while there is no history to corrupt.
 */
export function PersonActionBar({
  person,
  balance,
  openTransactions,
  currency,
  baseCurrency,
}: {
  person: Person;
  balance: PersonBalance;
  openTransactions: OpenTransaction[];
  /** The account's currency — every figure in this bar is denominated in it. */
  currency: string;
  /** The workspace currency, the default for a person who has not named one. */
  baseCurrency: string;
}) {
  const router = useRouter();
  const [addType, setAddType] = useState<TxnType | null>(null);
  const [settleOpen, setSettleOpen] = useState(false);
  const [editOpen, setEditOpen] = useState(false);
  const [confirm, setConfirm] = useState<
    'archive' | 'restore' | 'delete' | 'void-history' | null
  >(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const hasOutstanding =
    balance.outstanding_receivable > 0 || balance.outstanding_payable > 0;

  // What a retraction would actually touch. Both counts exclude voided rows
  // already, so an account that has been retracted once stops offering it.
  const liveEntries = balance.transaction_count;
  const hasHistory = liveEntries > 0 || balance.total_settled > 0;

  function run(operation: () => Promise<{ ok: boolean; error?: string }>, after?: () => void) {
    setError(null);
    startTransition(async () => {
      const result = await operation();
      if (!result.ok) {
        setError(result.error ?? 'That did not work. Please try again.');
        return;
      }
      setConfirm(null);
      after?.();
      router.refresh();
    });
  }

  return (
    <div className="flex flex-col items-stretch gap-2">
      {error ? <ErrorNote>{error}</ErrorNote> : null}

      <div className="flex flex-wrap gap-2">
        {hasOutstanding ? (
          <Button onClick={() => setSettleOpen(true)}>
            <SettleIcon className="size-4" />
            Settle
          </Button>
        ) : null}

        {/* Credit and debit are separate buttons rather than one "add" that
            asks which — the type is the decision, so it is the click. */}
        <Button
          variant="secondary"
          onClick={() => setAddType(TYPE_FOR_FLOW.person_to_owner)}
        >
          <ArrowDownIcon className="size-4 text-payable" />
          Add credit
        </Button>

        <Button
          variant="secondary"
          onClick={() => setAddType(TYPE_FOR_FLOW.owner_to_person)}
        >
          <ArrowUpIcon className="size-4 text-receivable" />
          Add debit
        </Button>

        {/* The two icon-only controls stay together when the row wraps on a
            narrow screen — split across lines they read as orphans. */}
        <div className="flex gap-1">
          <Button variant="ghost" onClick={() => setEditOpen(true)} aria-label="Edit details">
            <EditIcon className="size-4" />
          </Button>

          <Button
            variant="ghost"
            onClick={() => setConfirm(person.is_archived ? 'restore' : 'archive')}
            aria-label={person.is_archived ? 'Restore' : 'Archive'}
          >
            <ArchiveIcon className="size-4" />
          </Button>
        </div>
      </div>

      {/* Always offered, never silently absent. Removing the control when there
          is history reads as the action being broken rather than as it being
          unavailable, and it names no alternative — so it is disabled instead,
          carrying the count that blocks it and pointing at Archive. */}
      {/* The same test the server applies. Both counts exclude voided rows and
          delete_person() now counts live rows only, so the two agree — which
          they did not before: an account whose transactions had all been voided
          reported zero here, offered Delete, and was then refused. */}
      {!hasHistory ? (
        <button
          type="button"
          onClick={() => setConfirm('delete')}
          className="text-[0.75rem] text-ink-faint transition-colors duration-[var(--dur)] hover:text-payable"
        >
          Delete this person
        </button>
      ) : (
        <div className="space-y-1.5">
          <p className="text-[0.75rem] text-ink-faint">
            <span className="text-ink-muted">Delete this person</span>
            {' — '}
            {liveEntries > 0
              ? `${liveEntries} ${
                  liveEntries === 1 ? 'transaction' : 'transactions'
                } on this account.`
              : 'a settlement is still recorded here.'}{' '}
            Archive them instead.
          </p>

          {/*
            The way back from an account entered wrong. Deliberately the quietest
            control on the screen and never the one the eye lands on first: it is
            reached only by someone who came looking for it.
          */}
          <button
            type="button"
            onClick={() => setConfirm('void-history')}
            className="text-[0.75rem] text-ink-faint transition-colors duration-[var(--dur)] hover:text-payable"
          >
            Retract all history for this person
          </button>
        </div>
      )}

      <TransactionSheet
        open={addType !== null}
        onClose={() => setAddType(null)}
        currency={currency}
        mode="create"
        defaultType={addType ?? TYPE_FOR_FLOW.person_to_owner}
        person={{
          id: person.id,
          name: person.name,
          currency,
          default_currency: balance.default_currency,
        }}
      />

      <SettleSheet
        open={settleOpen}
        onClose={() => setSettleOpen(false)}
        balance={balance}
        openTransactions={openTransactions}
        currency={currency}
      />

      <PersonForm
        open={editOpen}
        onClose={() => setEditOpen(false)}
        person={person}
        baseCurrency={baseCurrency}
        openingMinor={balance.opening_minor}
      />

      <ConfirmDialog
        open={confirm === 'archive'}
        onClose={() => setConfirm(null)}
        onConfirm={() => run(() => setPersonArchived(person.id, true))}
        pending={pending}
        tone="primary"
        title={`Archive ${person.name}?`}
        confirmLabel="Archive"
        body={
          <>
            They are hidden from the people list and from your totals. Every transaction and
            settlement is kept, and you can restore them at any time.
          </>
        }
      />

      <ConfirmDialog
        open={confirm === 'restore'}
        onClose={() => setConfirm(null)}
        onConfirm={() => run(() => setPersonArchived(person.id, false))}
        pending={pending}
        tone="primary"
        title={`Restore ${person.name}?`}
        confirmLabel="Restore"
        body="They will appear in your people list and totals again."
      />

      <ConfirmDialog
        open={confirm === 'void-history'}
        onClose={() => setConfirm(null)}
        onConfirm={() =>
          run(() => voidPersonHistory(person.id, 'Retracted from the person page'))
        }
        pending={pending}
        title={`Retract everything for ${person.name}?`}
        confirmLabel="Retract all history"
        body={
          <>
            <p>
              Every transaction and settlement on this account is marked voided. The balance
              goes to zero and the entries disappear from your dashboard and activity feed.
            </p>
            <p className="mt-2">
              Nothing is deleted. The entries stay on this person&rsquo;s own timeline, marked
              voided, with their amounts and dates exactly as they were — that record is what
              makes this safe to do.
            </p>
            <p className="mt-2 text-ink-faint">
              Undoing this means restoring entries one at a time, so it is worth being sure.
            </p>
          </>
        }
      />

      <ConfirmDialog
        open={confirm === 'delete'}
        onClose={() => setConfirm(null)}
        onConfirm={() => run(() => deletePerson(person.id), () => router.push('/people'))}
        pending={pending}
        title={`Delete ${person.name}?`}
        confirmLabel="Delete"
        body="This cannot be undone. It is only possible because there are no transactions on this account."
      />
    </div>
  );
}
