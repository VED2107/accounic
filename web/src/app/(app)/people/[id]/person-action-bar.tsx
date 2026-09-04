'use client';

import { useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Button, ErrorNote } from '@/components/ui/primitives';
import { ConfirmDialog } from '@/components/ui/modal';
import { Menu, type MenuItemSpec } from '@/components/ui/menu';
import { ArrowDownIcon, ArrowUpIcon, SettleIcon } from '@/components/icons';
import { TransactionSheet } from '@/components/ledger/transaction-sheet';
import { SettleSheet } from '@/components/ledger/settle-sheet';
import { TransferSheet } from '@/components/ledger/transfer-sheet';
import { PersonForm } from '@/components/ledger/person-form';
import { deletePerson, setPersonArchived, voidPersonHistory } from '@/lib/actions';
import type { OpenTransaction, Person, PersonBalance, TxnType } from '@/lib/types';
import { TYPE_FOR_FLOW } from '@/lib/direction';

/**
 * Actions on a person account (context.md §9, §17).
 *
 * v1.11.0 — one primary action, two ordinary ones, everything else behind a
 * menu.
 *
 * This bar used to be five buttons, two icon buttons, and two lines of
 * destructive plain text, all at the same visual weight and all permanently on
 * screen. That is a control panel, not an account header: a reader looking for
 * "settle" had to pick it out of nine equal things, and "Retract all history"
 * sat one line under the primary call to action on every visit.
 *
 * The hierarchy now says what the screen is for:
 *
 *   Settle           filled, first, and present only when there is something
 *                    to settle — the product's headline interaction
 *   Add credit /     the two ordinary entries. Still two buttons rather than
 *   Add debit        one "add" that asks which, because the type IS the
 *                    decision and making it a click saves a step
 *   ⋯                transfer, edit, archive, and the two destructive routes,
 *                    which are reached only by someone who came looking
 *
 * The destructive items keep their explanations — the menu carries a
 * description line, so "Delete" can still say why it is unavailable and name
 * Archive as the thing to do instead, rather than simply being greyed.
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
  const [transferOpen, setTransferOpen] = useState(false);
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

  const items: MenuItemSpec[] = [
    {
      // Moving money between two of your own accounts is neither a credit nor a
      // debit — nothing is owed differently overall, it just sits somewhere
      // else. Hence its own item rather than a mode of "add".
      label: 'Transfer to another account',
      onSelect: () => setTransferOpen(true),
    },
    {
      label: 'Edit details',
      onSelect: () => setEditOpen(true),
    },
    person.is_archived
      ? {
          label: 'Restore',
          description: 'Show this account in your people list and totals again.',
          onSelect: () => setConfirm('restore'),
        }
      : {
          label: 'Archive',
          description: 'Hide from lists and totals. Every entry is kept.',
          onSelect: () => setConfirm('archive'),
        },
  ];

  if (hasHistory) {
    // The way back from an account entered wrong. Reached only by someone who
    // came looking for it — which, in a menu, is exactly what opening the menu
    // and reading to the bottom means.
    items.push({
      label: 'Retract all history',
      description: 'Void every entry. Nothing is deleted; the record stays, marked voided.',
      destructive: true,
      onSelect: () => setConfirm('void-history'),
    });
    items.push({
      label: 'Delete this person',
      // Listed and explained rather than absent. A missing Delete reads as the
      // action being broken; a disabled one that says what blocks it and names
      // the alternative answers the question it raises.
      description:
        liveEntries > 0
          ? `${liveEntries} ${liveEntries === 1 ? 'entry' : 'entries'} on this account. Archive instead.`
          : 'A settlement is recorded here. Archive instead.',
      destructive: true,
      disabled: true,
      onSelect: () => {},
    });
  } else {
    items.push({
      label: 'Delete this person',
      description: 'Possible only while the account has no history.',
      destructive: true,
      onSelect: () => setConfirm('delete'),
    });
  }

  return (
    <div className="flex flex-col items-stretch gap-3">
      {error ? <ErrorNote>{error}</ErrorNote> : null}

      {/* On a phone Settle takes a row of its own and the two entry buttons
          share the next one with the menu. The primary action must never be the
          one that wrapped, and the menu must never be the orphan on a line by
          itself — which is what a single wrapping flex row produced at 375px:
          two buttons, then a lone "…" on the row below with half a card of
          empty space beside it.

          `basis-0 flex-1` keeps the pair equal without percentage arithmetic,
          `min-w-0` lets them actually shrink, and the menu is `shrink-0`, so
          the row fits 360px without wrapping at all. */}
      <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:items-center">
        {hasOutstanding ? (
          <Button className="w-full sm:w-auto sm:min-w-32" onClick={() => setSettleOpen(true)}>
            <SettleIcon className="size-4" />
            Settle
          </Button>
        ) : null}

        <div className="flex items-center gap-2 sm:contents">
          <Button
            variant="secondary"
            className="min-w-0 flex-1 basis-0 sm:flex-none sm:basis-auto"
            onClick={() => setAddType(TYPE_FOR_FLOW.person_to_owner)}
          >
            <ArrowDownIcon className="size-4 text-payable" />
            Add credit
          </Button>

          <Button
            variant="secondary"
            className="min-w-0 flex-1 basis-0 sm:flex-none sm:basis-auto"
            onClick={() => setAddType(TYPE_FOR_FLOW.owner_to_person)}
          >
            <ArrowUpIcon className="size-4 text-receivable" />
            Add debit
          </Button>

          <Menu label={person.name} items={items} className="shrink-0 sm:ml-auto" />
        </div>
      </div>

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

      <TransferSheet
        open={transferOpen}
        onClose={() => setTransferOpen(false)}
        baseCurrency={baseCurrency}
        from={{
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
