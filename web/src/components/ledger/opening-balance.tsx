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
import { adjustOpeningBalance, setOpeningBalance, settleOpeningBalance } from '@/lib/actions';
import { TYPE_FOR_FLOW, entryLabel, txnLabel, type Flow } from '@/lib/direction';
import { formatApprox, formatMoney, minorToInput } from '@/lib/money';
import { fullDate, timeOfDay } from '@/lib/dates';
import { normaliseCode } from '@/lib/currencies';
import type {
  ActionResult,
  OpeningHistoryEntry,
  Person,
  PersonOpening,
  PositionSplit,
  TimelineEntry,
} from '@/lib/types';

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
  activity,
  position,
  currency,
  baseCurrency,
  openingMinor,
}: {
  person: Person;
  opening: PersonOpening | null;
  history: OpeningHistoryEntry[];
  /**
   * Credits, debits and settlements against the opening book
   * (db/migrations/0022). They live here and are deliberately absent from the
   * regular transactions below.
   */
  activity: TimelineEntry[];
  /** What is LEFT of the opening book — the figure the dashboard totals. */
  position: PositionSplit;
  /** The account's ledger currency — what the opening balance is denominated in. */
  currency: string;
  baseCurrency: string;
  /** The signed figure from person_balances, the authority on both sides. */
  openingMinor: number;
}) {
  const router = useRouter();
  const [editOpen, setEditOpen] = useState(false);
  const [settleOpen, setSettleOpen] = useState(false);
  const [adjustFlow, setAdjustFlow] = useState<Flow | null>(null);
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
                {/* Credit and Debit against the opening balance itself. They are
                    not the transaction actions wearing different labels: they call
                    a different action, write into the opening book, and never reach
                    the transactions below. The words go through lib/direction.ts,
                    so this section cannot mean something different by "Credit" than
                    the rest of the page does. */}
                <OpeningAction
                  tone="payable"
                  onClick={() => setAdjustFlow('person_to_owner')}
                >
                  {txnLabel(TYPE_FOR_FLOW.person_to_owner)}
                </OpeningAction>
                <OpeningAction
                  tone="receivable"
                  onClick={() => setAdjustFlow('owner_to_person')}
                >
                  {txnLabel(TYPE_FOR_FLOW.owner_to_person)}
                </OpeningAction>
                {position.position !== 0 ? (
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

            <div className="mt-3 border-t border-line pt-3">
              {/* What is LEFT of the opening book, which is the figure the
                  dashboard’s "Opening balance" total is built from. Stated here
                  so the two screens visibly agree. */}
              <p className="flex items-baseline justify-between gap-3">
                <span className="text-[0.75rem] font-medium text-ink-muted">Outstanding</span>
                <span
                  className={cn(
                    'tnum text-[0.875rem] font-semibold',
                    position.position > 0 && 'text-receivable',
                    position.position < 0 && 'text-payable',
                    position.position === 0 && 'text-ink-faint',
                  )}
                >
                  {formatMoney(Math.abs(position.position), currency)}
                </span>
              </p>
              <p className="mt-2 text-[0.75rem] leading-relaxed text-ink-faint">
                Kept apart from cash in hand. The account position above is the two added
                together, and neither screen ever counts this figure twice.
              </p>
            </div>
          </div>
        ) : (
          <div className="flex flex-wrap items-center justify-between gap-3 px-5 py-4">
            <p className="text-[0.8125rem] text-ink-muted">
              No opening balance. This account started at zero.
            </p>
            <OpeningAction onClick={() => setEditOpen(true)}>Add one</OpeningAction>
          </div>
        )}

        {/* The opening book’s own history: credits, debits and its own
            settlements. These are deliberately absent from the regular
            transactions below — that is the whole point of the section. */}
        {activity.length > 0 ? (
          <div className="border-t border-line bg-sunken px-5 py-3">
            <p className="text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
              Opening balance activity
            </p>
            <ul className="mt-1.5 divide-y divide-line">
              {activity.map((row) => (
                <li key={row.id}>
                  <OpeningActivityRow row={row} currency={currency} />
                </li>
              ))}
            </ul>
          </div>
        ) : null}

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
          position={position}
          currency={currency}
        />
      ) : null}

      {opening && adjustFlow ? (
        <OpeningAdjustSheet
          open
          onClose={() => setAdjustFlow(null)}
          person={person}
          opening={opening}
          currency={currency}
          flow={adjustFlow}
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

/**
 * One row of the opening book's history.
 *
 * Reads exactly like a timeline row and is deliberately not one: it lives in
 * this section, and the regular transactions never contain it.
 */
function OpeningActivityRow({ row, currency }: { row: TimelineEntry; currency: string }) {
  const settlement = row.entry_kind === 'settlement';
  const receivable = settlement
    ? row.money_direction === 'in'
    : row.entry_type === 'credit';

  const label = entryLabel(row.entry_kind, row.entry_type);
  const minor = row.entry_amount_minor ?? row.amount_minor;
  const code = normaliseCode(row.entry_currency) || currency;

  return (
    <div className="flex items-start justify-between gap-3 py-1.5">
      <div className="min-w-0">
        <p className="truncate text-[0.8125rem] font-medium text-ink-muted">{label}</p>
        <p className="truncate text-[0.75rem] text-ink-faint">
          {fullDate(row.entry_date)}
          {row.note ? ` · ${row.note}` : ''}
        </p>
      </div>
      <p
        className={cn(
          'tnum shrink-0 text-[0.8125rem] font-semibold',
          settlement && 'text-ink-muted',
          !settlement && receivable && 'text-receivable',
          !settlement && !receivable && 'text-payable',
        )}
      >
        {settlement ? '' : receivable ? '+' : '−'}
        {formatMoney(minor, code)}
      </p>
    </div>
  );
}

function OpeningAction({
  children,
  onClick,
  tone = 'default',
}: {
  children: React.ReactNode;
  onClick: () => void;
  tone?: 'default' | 'danger' | 'primary' | 'receivable' | 'payable';
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'rounded-field border bg-surface px-3 py-1.5 text-[0.8125rem] font-medium',
        'transition-[border-color,background-color,color] duration-[var(--dur)] ease-[var(--ease)]',
        tone === 'danger' || tone === 'payable'
          ? 'border-payable-line text-payable hover:bg-payable-soft'
          : tone === 'receivable'
            ? 'border-receivable-line text-receivable hover:bg-receivable-soft'
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
  position,
  currency,
}: {
  open: boolean;
  onClose: () => void;
  person: Person;
  opening: PersonOpening;
  /**
   * What is left of the whole opening BOOK, not of the balance row alone
   * (db/migrations/0022).
   *
   * The two differ the moment a credit or debit is recorded against the
   * opening balance, and the difference is not cosmetic:
   * `settle_opening_balance()` settles the book and refuses an amount larger
   * than the book's remainder, so a sheet that offered the balance row's own
   * remainder would default to a figure the server rejects.
   */
  position: PositionSplit;
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
  // Which way money must move to retire the book, derived from the book's net
  // position exactly as the server derives it — not from the balance row,
  // which an adjustment can outweigh.
  const incoming = position.position > 0;
  const outstanding = Math.abs(position.position);

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
            {formatMoney(outstanding, currency)}
          </p>
          {position.settled > 0 ? (
            <p className="mt-1 text-[0.75rem] text-ink-faint">
              {formatMoney(position.settled, currency)} already settled against the opening
              balance
            </p>
          ) : null}
        </div>

        <AmountInput
          currency={currency}
          autoFocus
          max={outstanding}
          defaultValue={minorToInput(outstanding, currency)}
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

/**
 * Credit and debit against the opening balance (db/migrations/0022).
 *
 * Deliberately NOT the transaction sheet. What this records is not a
 * transaction: it is a correction to the figure the account was carried in
 * with, and it must never appear among the regular transactions, never move
 * cash in hand, and never be counted twice on the dashboard. The database
 * enforces all four through `adjust_opening_balance()`, which is the only RPC
 * this sheet reaches.
 *
 * The amount is typed and recorded in the account's own denomination — the
 * opening balance is stored in it, and this adjusts that book. A correction in
 * another currency is a different question and belongs on the edit form, where
 * the whole opening figure is restated at a rate that is frozen on the row.
 */
function OpeningAdjustSheet({
  open,
  onClose,
  person,
  opening,
  currency,
  flow,
}: {
  open: boolean;
  onClose: () => void;
  person: Person;
  opening: PersonOpening;
  currency: string;
  flow: Flow;
}) {
  const router = useRouter();
  const toast = useToast();
  const [state, formAction] = useActionState<ActionResult<unknown> | null, FormData>(
    adjustOpeningBalance as (
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
      title: `${txnLabel(TYPE_FOR_FLOW[flow])} recorded against the opening balance`,
      body: 'It is not a regular transaction and does not affect cash in hand.',
    });
  }, [state, onClose, router, toast, flow]);

  const fieldError = (field: string) =>
    state && !state.ok && state.field === field ? state.error : undefined;

  const firstName = person.name.split(' ')[0];
  const label = txnLabel(TYPE_FOR_FLOW[flow]);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={`${label} the opening balance`}
      description="This corrects what the account opened with. It is not a transaction, and it will not appear among them."
    >
      <form action={formAction} className="space-y-5" noValidate>
        {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}

        <input type="hidden" name="person_id" value={person.id} />
        {/* The stored enum, resolved by lib/direction.ts and nowhere else. */}
        <input type="hidden" name="type" value={TYPE_FOR_FLOW[flow]} />
        <input type="hidden" name="entry_currency" value={currency} />
        <input type="hidden" name="account_currency" value={currency} />

        <div className="rounded-card border border-line bg-sunken px-4 py-3">
          <p className="text-[0.75rem] text-ink-muted">What this account opened with</p>
          <p className="money tnum mt-1 text-[1.25rem] font-semibold text-ink">
            {formatMoney(opening.entry_amount_minor, opening.entry_currency)}
          </p>
          <p className="mt-1 text-[0.75rem] leading-relaxed text-ink-faint">
            {flow === 'owner_to_person'
              ? `A debit increases what ${firstName} owed you when the account opened.`
              : `A credit increases what you owed ${firstName} when the account opened.`}
          </p>
        </div>

        <AmountInput currency={currency} autoFocus error={fieldError('amount')} />

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Date" htmlFor="opening-adjust-date" error={fieldError('date')}>
            <Input
              id="opening-adjust-date"
              name="date"
              type="date"
              max={todayIso()}
              defaultValue={todayIso()}
              required
            />
          </Field>
          <Field label="Note" htmlFor="opening-adjust-note" hint="Optional">
            <Input
              id="opening-adjust-note"
              name="note"
              placeholder="Opening figure was short"
              maxLength={500}
            />
          </Field>
        </div>

        <SubmitRow label={`Record ${label.toLowerCase()}`} onCancel={onClose} />
      </form>
    </Modal>
  );
}
