'use client';

import { useActionState, useEffect, useRef, useState, useTransition } from 'react';
import { useRouter } from 'next/navigation';
import { Badge, Card, ErrorNote, Field, Input, cn } from '@/components/ui/primitives';
import { ConfirmDialog, Modal } from '@/components/ui/modal';
import { AmountInput } from '@/components/ledger/amount-input';
import { SubmitRow } from '@/components/ledger/transaction-sheet';
import { useToast } from '@/components/ui/toast';
import { todayIso } from '@/lib/dates';
import { PersonForm } from '@/components/ledger/person-form';
import { RateNote } from '@/components/ledger/conversion';
import { setOpeningBalance, settleOpeningBalance } from '@/lib/actions';
import { formatApprox, formatMoney, minorToInput } from '@/lib/money';
import { fullDate, timeOfDay } from '@/lib/dates';
import { normaliseCode } from '@/lib/currencies';
import type { ActionResult, OpeningHistoryEntry, Person, PersonOpening } from '@/lib/types';

/**
 * The opening balance, in its own section (upgrade §46).
 *
 * It used to sit in the timeline wearing a Credit or Debit label and offering
 * a Settle button, which said three untrue things at once: that it happened on
 * a particular day, that it was an ordinary entry, and that somebody could pay
 * it off on its own. It is none of those. It is what the account was carried in
 * with — so it gets a section, the two actions that actually apply to it
 * (change it, clear it), and no others.
 *
 * What has not changed: it still counts towards the current position, in full.
 * The card says so, because a figure shown apart from the balance invites the
 * question of whether it is in the balance.
 */
export function OpeningBalanceCard({
  person,
  opening,
  history,
  currency,
  baseCurrency,
  openingMinor,
}: {
  person: Person;
  opening: PersonOpening | null;
  history: OpeningHistoryEntry[];
  /** The account's ledger currency — what the opening balance is denominated in. */
  currency: string;
  baseCurrency: string;
  /** The signed figure from person_balances, the authority on both sides. */
  openingMinor: number;
}) {
  const router = useRouter();
  const [editOpen, setEditOpen] = useState(false);
  const [settleOpen, setSettleOpen] = useState(false);
  const [confirmClear, setConfirmClear] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function clear() {
    setError(null);
    startTransition(async () => {
      // The same action the edit form uses, with the direction that means
      // "there isn't one". The database retracts the existing row rather than
      // deleting it, so the correction stays visible in the history below.
      const form = new FormData();
      form.set('opening_direction', 'none');
      form.set('currency', normaliseCode(person.currency ?? currency));
      form.set('opening_account_currency', normaliseCode(currency));

      const result = await setOpeningBalance(person.id, null, form);
      if (!result.ok) {
        setError(result.error);
        return;
      }
      setConfirmClear(false);
      router.refresh();
    });
  }

  const firstName = person.name.split(' ')[0];

  return (
    <section className="mt-6" aria-labelledby="opening-balance-heading">
      <div className="mb-2 flex items-center justify-between gap-3 px-1">
        <h2
          id="opening-balance-heading"
          className="text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint"
        >
          Opening balance
        </h2>
        <span aria-hidden className="h-px flex-1 bg-line" />
      </div>

      <Card>
        {error ? (
          <div className="px-5 pt-4">
            <ErrorNote>{error}</ErrorNote>
          </div>
        ) : null}

        {opening ? (
          <div className="px-5 py-4">
            <div className="flex flex-wrap items-start justify-between gap-4">
              <div className="min-w-0">
                {/* The original figure leads, in the currency it was stated in.
                    A dirham opening balance is 400 AED and says so — the rupee
                    equivalent is a second line, never a replacement. */}
                <p
                  className={cn(
                    'money tnum text-[1.375rem] font-semibold',
                    openingMinor > 0 && 'text-receivable',
                    openingMinor < 0 && 'text-payable',
                    openingMinor === 0 && 'text-ink',
                  )}
                >
                  {formatMoney(opening.entry_amount_minor, opening.entry_currency)}
                </p>

                {/* One equivalent, and only when it says something the line
                    above does not. */}
                <Equivalent opening={opening} currency={currency} baseCurrency={baseCurrency} />

                <p className="mt-1.5 text-[0.8125rem] font-medium text-ink-muted">
                  {openingMinor > 0
                    ? `${firstName} owed you this when the account opened`
                    : `You owed ${firstName} this when the account opened`}
                </p>

                {/* Its own settlement, stated in its own section rather than
                    left to be inferred from the account total. */}
                {opening.settled_minor > 0 ? (
                  <p className="mt-1 flex flex-wrap items-center gap-2 text-[0.8125rem]">
                    <Badge tone={opening.remaining_minor === 0 ? 'receivable' : 'muted'}>
                      {opening.remaining_minor === 0 ? 'Settled' : 'Part settled'}
                    </Badge>
                    <span className="text-ink-faint">
                      {formatMoney(opening.settled_minor, currency)} settled
                      {opening.remaining_minor > 0
                        ? ` · ${formatMoney(opening.remaining_minor, currency)} left`
                        : ''}
                    </span>
                  </p>
                ) : null}

                <RateNote
                  className="mt-1 block"
                  enteredMinor={opening.entered_amount_minor}
                  enteredCurrency={opening.entered_currency}
                  rateE9={opening.exchange_rate_e9}
                  rateSource={opening.exchange_rate_source}
                  accountCurrency={currency}
                  conversionMode={opening.conversion_mode}
                  autoConvertedMinor={opening.auto_converted_amount_minor}
                />

                <p className="mt-1 text-[0.75rem] text-ink-faint">
                  Dated {fullDate(opening.entry_date)}
                  {' · recorded '}
                  {fullDate(opening.created_at)} at {timeOfDay(opening.created_at)}
                </p>
              </div>

              {/* The three things that actually apply to an opening balance.
                  Settling it is its OWN action, separate from the row action
                  the regular transactions use — two sections, two settlement
                  paths, one page. The database enforces that separation: a
                  settlement may name an opening balance only through this. */}
              <div className="flex shrink-0 flex-wrap justify-end gap-2">
                {opening.remaining_minor > 0 ? (
                  <OpeningAction tone="primary" onClick={() => setSettleOpen(true)}>
                    Settle
                  </OpeningAction>
                ) : null}
                <OpeningAction onClick={() => setEditOpen(true)}>Edit</OpeningAction>
                <OpeningAction tone="danger" onClick={() => setConfirmClear(true)}>
                  Remove
                </OpeningAction>
              </div>
            </div>

            <p className="mt-3 border-t border-line pt-3 text-[0.75rem] text-ink-faint">
              Counted in the current position above, in full. It is not a credit or a debit,
              and it is settled here rather than from the transactions below.
            </p>
          </div>
        ) : (
          <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-4">
            <p className="text-[0.8125rem] text-ink-muted">
              No opening balance. This account started at zero.
            </p>
            <OpeningAction onClick={() => setEditOpen(true)}>Add one</OpeningAction>
          </div>
        )}

        {history.length > 0 ? (
          <div className="border-t border-line bg-sunken px-5 py-3">
            <p className="text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
              Replaced
            </p>
            <ul className="mt-1.5 space-y-1">
              {history.map((row) => (
                <li key={row.id} className="flex flex-wrap items-baseline gap-2">
                  <span className="tnum text-[0.8125rem] text-ink-muted line-through">
                    {formatMoney(row.entry_amount_minor, row.entry_currency)}
                  </span>
                  <Badge tone="muted">Retracted</Badge>
                  <span className="text-[0.75rem] text-ink-faint">
                    dated {fullDate(row.entry_date)}
                  </span>
                </li>
              ))}
            </ul>
            <p className="mt-2 text-[0.75rem] text-ink-faint">
              Replacing an opening balance retracts the previous one rather than editing it, so
              the correction stays visible. These affect no balance.
            </p>
          </div>
        ) : null}
      </Card>

      <PersonForm
        open={editOpen}
        onClose={() => setEditOpen(false)}
        person={person}
        baseCurrency={baseCurrency}
        openingMinor={openingMinor}
      />

      {opening ? (
        <OpeningSettleSheet
          open={settleOpen}
          onClose={() => setSettleOpen(false)}
          person={person}
          opening={opening}
          currency={currency}
        />
      ) : null}

      <ConfirmDialog
        open={confirmClear}
        onClose={() => setConfirmClear(false)}
        onConfirm={clear}
        pending={pending}
        title="Remove this opening balance?"
        confirmLabel="Remove"
        body={
          <>
            <p>
              The current position drops by{' '}
              {formatMoney(Math.abs(openingMinor), currency)}, because the account no longer
              starts anywhere but zero.
            </p>
            <p className="mt-2 text-ink-faint">
              Nothing is deleted. The entry is retracted and stays listed here as history, with
              its amount, currency, rate and date exactly as they were.
            </p>
          </>
        }
      />
    </section>
  );
}

/**
 * The one equivalent worth printing under the original figure.
 *
 * The ledger figure when the opening balance was converted into this account,
 * otherwise the workspace figure for an account kept in a foreign currency —
 * never both, and never the equivalent on its own. The same rule the timeline
 * rows follow, so the two sections of the page read identically.
 */
function Equivalent({
  opening,
  currency,
  baseCurrency,
}: {
  opening: PersonOpening;
  currency: string;
  baseCurrency: string;
}) {
  const entryCurrency = normaliseCode(opening.entry_currency) || currency;
  const base = normaliseCode(opening.base_currency) || normaliseCode(baseCurrency);

  const equivalent =
    entryCurrency !== currency
      ? { minor: opening.amount_minor, currency }
      : base && base !== currency && opening.amount_base_minor != null
        ? { minor: opening.amount_base_minor, currency: base }
        : null;

  if (!equivalent) return null;

  return (
    <p className="tnum mt-0.5 text-[0.875rem] text-ink-faint">
      {formatApprox(equivalent.minor, equivalent.currency)}
    </p>
  );
}

function OpeningAction({
  children,
  onClick,
  tone = 'default',
}: {
  children: React.ReactNode;
  onClick: () => void;
  tone?: 'default' | 'danger' | 'primary';
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
          : tone === 'primary'
            ? 'border-accent-line bg-accent-soft text-accent hover:bg-accent-soft/70'
            : 'border-line-strong text-ink hover:bg-sunken',
      )}
    >
      {children}
    </button>
  );
}

/**
 * Settling the opening balance — that entry, and nothing else (upgrade §48).
 *
 * Deliberately not the settle sheet the regular transactions use. That one asks
 * which side is being settled and against which row; neither question applies
 * here. There is one opening balance, its direction is a property of the entry,
 * and the server derives it — so this asks for an amount and a date and nothing
 * else, and defaults the amount to closing it, which is the common case.
 */
function OpeningSettleSheet({
  open,
  onClose,
  person,
  opening,
  currency,
}: {
  open: boolean;
  onClose: () => void;
  person: Person;
  opening: PersonOpening;
  currency: string;
}) {
  const router = useRouter();
  const toast = useToast();
  const [state, formAction] = useActionState<ActionResult<unknown> | null, FormData>(
    settleOpeningBalance as (
      prev: ActionResult<unknown> | null,
      formData: FormData,
    ) => Promise<ActionResult<unknown>>,
    null,
  );

  // `state` stays `ok` for the life of the component, so the success effect is
  // keyed on the result's identity rather than on its truth.
  const handled = useRef<ActionResult<unknown> | null>(null);

  useEffect(() => {
    if (!state?.ok || handled.current === state) return;
    handled.current = state;
    onClose();
    router.refresh();
    toast.show({
      tone: 'success',
      title: 'Opening balance settled',
      body: 'The current position has been recalculated.',
    });
  }, [state, onClose, router, toast]);

  const fieldError = (field: string) =>
    state && !state.ok && state.field === field ? state.error : undefined;

  const firstName = person.name.split(' ')[0];
  const incoming = opening.signed_minor > 0;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Settle the opening balance"
      description={
        incoming
          ? `Money received from ${firstName} against what the account opened with.`
          : `Money paid to ${firstName} against what the account opened with.`
      }
    >
      <form action={formAction} className="space-y-5" noValidate>
        {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}

        <input type="hidden" name="person_id" value={person.id} />
        {/* The amount is typed and recorded in the account's own denomination:
            the opening balance is stored in it, and this settles that entry. */}
        <input type="hidden" name="entry_currency" value={currency} />
        <input type="hidden" name="account_currency" value={currency} />

        <div className="rounded-card border border-line bg-sunken px-4 py-3">
          <p className="text-[0.75rem] text-ink-muted">Outstanding on the opening balance</p>
          <p className="money tnum mt-1 text-[1.25rem] font-semibold text-ink">
            {formatMoney(opening.remaining_minor, currency)}
          </p>
          {opening.settled_minor > 0 ? (
            <p className="mt-1 text-[0.75rem] text-ink-faint">
              {formatMoney(opening.settled_minor, currency)} already settled of{' '}
              {formatMoney(opening.amount_minor, currency)}
            </p>
          ) : null}
        </div>

        <AmountInput
          currency={currency}
          autoFocus
          max={opening.remaining_minor}
          defaultValue={minorToInput(opening.remaining_minor, currency)}
          error={fieldError('amount')}
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Date" htmlFor="opening-settle-date" error={fieldError('date')}>
            <Input
              id="opening-settle-date"
              name="date"
              type="date"
              max={todayIso()}
              defaultValue={todayIso()}
              required
            />
          </Field>
          <Field label="Note" htmlFor="opening-settle-note" hint="Optional">
            <Input
              id="opening-settle-note"
              name="note"
              placeholder="Cash received"
              maxLength={500}
            />
          </Field>
        </div>

        <SubmitRow label="Record settlement" onCancel={onClose} />
      </form>
    </Modal>
  );
}
