'use client';

import { useActionState, useCallback, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Modal } from '@/components/ui/modal';
import {
  Button,
  ErrorNote,
  Field,
  FormSection,
  FormSections,
  Input,
  Select,
  cn,
} from '@/components/ui/primitives';
import { SettledMark } from '@/components/ui/toast';
import { AmountInput } from '@/components/ledger/amount-input';
import { CurrencySelect } from '@/components/ledger/currency-select';
import { ConversionFields, ConversionPanel, useRate } from '@/components/ledger/conversion';
import { SubmitRow } from '@/components/ledger/transaction-sheet';
import { createSettlement } from '@/lib/actions';
import { formatMoney } from '@/lib/money';
import { friendlyDate, todayIso } from '@/lib/dates';
import type { ActionResult, OpenTransaction, PersonBalance, SettlementDirection } from '@/lib/types';

/**
 * Settlement (context.md §9).
 *
 * The direction is decided for the user whenever it can be: an account that is
 * only receivable can only be settled by money coming in. The choice is shown
 * only when the person genuinely owes and is owed at the same time.
 *
 * Partial is the default assumption — the amount is free to edit, the quarter
 * steps make the common cases one tap, and the arithmetic the user would
 * otherwise do in their head (outstanding, settling, what is left) is done live
 * above the field. The database still rejects anything above the ceiling, so a
 * stale screen cannot over-settle.
 *
 * Closing a debt is the most satisfying thing this product does, so it is the
 * one place given a real success state rather than a toast and a dismissal.
 */
export function SettleSheet({
  open,
  onClose,
  balance,
  openTransactions,
  currency,
  presetTransactionId,
}: {
  open: boolean;
  onClose: () => void;
  balance: PersonBalance;
  openTransactions: OpenTransaction[];
  currency: string;
  presetTransactionId?: string;
}) {
  const router = useRouter();
  const canReceive = balance.outstanding_receivable > 0;
  const canPay = balance.outstanding_payable > 0;
  const bothSides = canReceive && canPay;

  const [direction, setDirection] = useState<SettlementDirection>(canReceive ? 'in' : 'out');
  const [transactionId, setTransactionId] = useState<string>(presetTransactionId ?? '');
  const [amount, setAmount] = useState<number | null>(null);
  const [done, setDone] = useState<{ amount: number; remaining: number } | null>(null);

  /// The currency the payment is being TYPED in. Follows the account until the
  /// user says otherwise, because the ordinary case should cost no decisions.
  const [entryCurrency, setEntryCurrency] = useState(currency);
  const foreign = entryCurrency !== currency;
  const rate = useRate(entryCurrency, currency);

  /**
   * What the typed amount comes to in the ACCOUNT's currency.
   *
   * Reported by the conversion panel, which owns the rate and both overrides.
   * Null until there is an answer. Before v1.11.0 this sheet did the arithmetic
   * on the typed figure alone — so settling a rupee account with AED 40 printed
   * "Settling ₹40.00" and "Remaining" computed from it. The number was in the
   * wrong currency and every figure derived from it was wrong with it.
   */
  const [convertedMinor, setConvertedMinor] = useState<number | null>(null);
  const onResolved = useCallback((value: number | null) => setConvertedMinor(value), []);

  const [state, formAction] = useActionState<ActionResult<unknown> | null, FormData>(
    createSettlement,
    null,
  );

  // Reset when the sheet opens — and only then. Depending on `openTransactions`
  // or `balance` here would re-run this on every server refresh, including the
  // refresh a successful settlement triggers, which would wipe the success state
  // the settlement had just produced.
  useEffect(() => {
    if (!open) return;
    const preset = presetTransactionId
      ? openTransactions.find((t) => t.id === presetTransactionId)
      : undefined;
    setTransactionId(presetTransactionId ?? '');
    setDirection(preset ? (preset.type === 'credit' ? 'in' : 'out') : canReceive ? 'in' : 'out');
    setAmount(null);
    setDone(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  const selected = openTransactions.find((t) => t.id === transactionId);
  const matching = openTransactions.filter((t) =>
    direction === 'in' ? t.type === 'credit' : t.type === 'debit',
  );

  // The ceiling: a named transaction's remaining amount, otherwise the whole
  // outstanding side.
  const max = selected
    ? selected.remaining_minor
    : direction === 'in'
      ? balance.outstanding_receivable
      : balance.outstanding_payable;

  // The settlement in the account's own currency — the only denomination the
  // ceiling, the remainder and the ledger are expressed in.
  const ledgerMinor = foreign ? convertedMinor : amount;
  const settling = Math.min(Math.max(ledgerMinor ?? 0, 0), max);
  const remaining = max - settling;
  // Over the ceiling is possible only on a foreign entry, where the input has
  // no `max` to clamp against — the figure is not known until it is converted.
  // The database refuses it either way; saying so before the submit is kinder
  // than saying so after.
  const overCeiling = ledgerMinor !== null && ledgerMinor > max;
  const nothingToSettle = !canReceive && !canPay;

  // useActionState keeps the last result for the life of the component, so a
  // success effect must be keyed on the result's identity — otherwise simply
  // reopening this sheet replays the success it recorded last time.
  const handled = useRef<ActionResult<unknown> | null>(null);
  const snapshot = useRef<{ settling: number; max: number } | null>(null);

  useEffect(() => {
    if (!state?.ok || handled.current === state) return;
    handled.current = state;

    // `settling`/`remaining` are derived from props that the action's own
    // revalidation has already updated — reading them here would report the
    // settlement twice over. The snapshot taken at submit is the truth.
    const submitted = snapshot.current;
    const settled = submitted?.settling ?? settling;
    const left = submitted ? submitted.max - submitted.settling : remaining;
    setDone({ amount: settled, remaining: left });
    // The page behind re-reads its balance from the database rather than
    // guessing at it — the figure the user sees is the one that was committed.
    router.refresh();
    // No toast here. This sheet shows its own success state with the figures on
    // it, and the balance behind has already animated to its new value — a
    // toast saying the same thing a third time is noise, and on a phone it
    // lands on top of the panel it is describing.
  }, [state, settling, remaining, router]);

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={done ? 'Settled' : `Settle with ${balance.name}`}
      description={
        done
          ? undefined
          : direction === 'in'
            ? `Money received from ${balance.name}.`
            : `Money paid to ${balance.name}.`
      }
    >
      {done ? (
        <SettlementSuccess
          amount={done.amount}
          remaining={done.remaining}
          direction={direction}
          currency={currency}
          name={balance.name}
          onClose={onClose}
        />
      ) : nothingToSettle ? (
        <p className="py-6 text-center text-[0.8125rem] text-ink-muted">
          Nothing is outstanding with {balance.name}.
        </p>
      ) : (
        <form
          action={formAction}
          onSubmit={() => {
            snapshot.current = { settling, max };
          }}
          className="space-y-5"
          noValidate
        >
          {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}

          <input type="hidden" name="person_id" value={balance.person_id} />
          <input type="hidden" name="direction" value={direction} />
          <input type="hidden" name="transaction_id" value={transactionId} />
          {/*
            A settlement may be handed over in a currency the account is not kept
            in — a dirham account paid off in rupees. `create_settlement()` has
            taken the conversion arguments since db/migrations/0011; the sheet
            simply was not offering them, and told the user to put the real
            figure in the note instead.

            The ceiling is the one thing that cannot cross: it is an
            account-currency figure, so it is applied only while the two agree.
            Typed in another currency, the database's own over-settlement guard
            is what enforces it.
          */}

          <FormSections>
            {bothSides || matching.length > 0 ? (
              <FormSection title="What is being settled">
                {bothSides ? (
                  <fieldset>
                    <legend className="sr-only">Which side</legend>
                    <div className="grid grid-cols-2 gap-2">
                      <SideOption
                        active={direction === 'in'}
                        tone="receivable"
                        title="I received"
                        amount={formatMoney(balance.outstanding_receivable, currency, { base: currency })}
                        onClick={() => {
                          setDirection('in');
                          setTransactionId('');
                          setAmount(null);
                        }}
                      />
                      <SideOption
                        active={direction === 'out'}
                        tone="payable"
                        title="I paid"
                        amount={formatMoney(balance.outstanding_payable, currency, { base: currency })}
                        onClick={() => {
                          setDirection('out');
                          setTransactionId('');
                          setAmount(null);
                        }}
                      />
                    </div>
                  </fieldset>
                ) : null}

                {matching.length > 0 ? (
                  <Field
                    label="Against"
                    htmlFor="against"
                    hint="Leave on the whole account to settle the oldest entries first."
                  >
                    <Select
                      id="against"
                      value={transactionId}
                      onChange={(event) => {
                        setTransactionId(event.target.value);
                        setAmount(null);
                      }}
                    >
                      <option value="">The whole account</option>
                      {matching.map((txn) => (
                        <option key={txn.id} value={txn.id}>
                          {friendlyDate(txn.transaction_date)} ·{' '}
                          {formatMoney(txn.remaining_minor, currency, { base: currency })} left
                          {txn.description ? ` · ${txn.description}` : ''}
                        </option>
                      ))}
                    </Select>
                  </Field>
                ) : null}
              </FormSection>
            ) : null}

            {/* ----------------------------------------------------------------
                The settlement, as a chain the reader can follow end to end
                (v1.11.0).

                A settlement is one of the two financial acts this product
                performs, and the reader has to be able to answer four questions
                in order without doing any arithmetic:

                  what is owed   →   what I am paying   →   in what, at what
                  rate   →   and therefore what this settles

                They used to be scattered: a three-cell strip printed the
                arithmetic ABOVE the field it depended on — so on opening the
                sheet it read "Settling 0.00, Remaining <the whole balance>",
                which is an answer to a question nobody had asked yet — and the
                result of a foreign settlement was never stated in the account's
                currency at all. Now the balance due anchors the top, the entry
                sits under it, the rate under that, and the resolved figure
                closes it.
                ---------------------------------------------------------------- */}
            <FormSection title="Settlement" aside={foreign ? `Account keeps ${currency}` : currency}>
              <div className="flex items-baseline justify-between gap-4 rounded-card border border-line bg-sunken px-4 py-3">
                <span className="text-[0.8125rem] text-ink-muted">
                  Balance due
                  {selected ? ' on this entry' : ''}
                </span>
                <span className="money text-ink">
                  {formatMoney(max, currency, { base: currency })}
                </span>
              </div>

              <div className="grid gap-4 sm:grid-cols-[1fr_auto]">
                <AmountInput
                  currency={entryCurrency}
                  autoFocus
                  max={foreign ? undefined : max}
                  onValidChange={setAmount}
                  label="Settlement amount"
                  error={state && !state.ok && state.field === 'amount' ? state.error : undefined}
                />
                <CurrencySelect
                  name="entry_currency_visible"
                  label="Settlement currency"
                  value={entryCurrency}
                  onChange={setEntryCurrency}
                  hint={foreign ? undefined : 'Account currency'}
                  className="sm:w-56"
                />
              </div>

              {/* Both overrides, because both questions are real: the rate may
                  be wrong, and the amount that actually arrived may differ from
                  what any rate implies once a bank has taken its cut. Renders
                  nothing at all on a same-currency settlement, which is most of
                  them. */}
              <ConversionPanel
                amountMinor={amount}
                from={entryCurrency}
                to={currency}
                state={rate}
                onResolved={onResolved}
              />
              <ConversionFields
                entryCurrency={entryCurrency}
                accountCurrency={currency}
                state={rate}
              />

              {/* The end of the chain. One figure, in the account's currency,
                  named for what it does to the reader's money — and under it,
                  what is left. */}
              <div
                className={cn(
                  'rounded-card border px-4 py-3.5',
                  'transition-[border-color,background-color] duration-[var(--dur)] ease-[var(--ease)]',
                  settling === 0
                    ? 'border-line bg-sunken'
                    : direction === 'in'
                      ? 'border-receivable-line bg-receivable-soft'
                      : 'border-payable-line bg-payable-soft',
                )}
                aria-live="polite"
              >
                <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1">
                  <span className="text-[0.8125rem] font-medium text-ink">
                    {direction === 'in' ? 'You’ll receive' : 'You’ll pay'}
                  </span>
                  <span
                    className={cn(
                      'money-lg',
                      settling === 0
                        ? 'text-ink-faint'
                        : direction === 'in'
                          ? 'text-receivable'
                          : 'text-payable',
                    )}
                  >
                    {formatMoney(settling, currency, { base: currency })}
                  </span>
                </div>

                <div className="mt-2 flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 border-t border-line/70 pt-2">
                  <span className="text-[0.75rem] text-ink-muted">
                    {remaining === 0 && settling > 0 ? 'Closes the balance' : 'Remaining after this'}
                  </span>
                  <span
                    className={cn(
                      'money-sm',
                      remaining === 0 && settling > 0 ? 'text-ink' : 'text-ink-muted',
                    )}
                  >
                    {formatMoney(remaining, currency, { base: currency })}
                  </span>
                </div>

                {overCeiling ? (
                  <p role="alert" className="mt-2 text-[0.8125rem] leading-relaxed text-payable">
                    That comes to more than the{' '}
                    {formatMoney(max, currency, { base: currency })} outstanding. Reduce it, or
                    settle the difference as a separate entry — the ledger will refuse an
                    over-settlement.
                  </p>
                ) : null}
              </div>
            </FormSection>

            <FormSection title="Details">
              <div className="grid gap-4 sm:grid-cols-2">
                <Field label="Date" htmlFor="settle-date">
                  <Input
                    id="settle-date"
                    name="date"
                    type="date"
                    max={todayIso()}
                    defaultValue={todayIso()}
                    required
                  />
                </Field>
                <Field label="Note" htmlFor="settle-note" hint="Optional">
                  <Input
                    id="settle-note"
                    name="note"
                    placeholder={direction === 'in' ? 'Cash received' : 'Paid by UPI'}
                    maxLength={500}
                  />
                </Field>
              </div>
            </FormSection>
          </FormSections>

          <SubmitRow
            label="Settle now"
            tone={direction === 'in' ? 'receivable' : 'payable'}
            onCancel={onClose}
          />
        </form>
      )}
    </Modal>
  );
}

/* -------------------------------------------------------------------------- */

function SettlementSuccess({
  amount,
  remaining,
  direction,
  currency,
  name,
  onClose,
}: {
  amount: number;
  remaining: number;
  direction: SettlementDirection;
  currency: string;
  name: string;
  onClose: () => void;
}) {
  return (
    <div className="flex flex-col items-center py-3 text-center">
      <SettledMark />
      <p className="mt-4 font-display text-[1.125rem] font-semibold tracking-tight text-ink">
        Settlement recorded
      </p>
      <p className="mt-1 text-[0.8125rem] text-ink-muted">
        {direction === 'in' ? 'Received' : 'Paid'} {formatMoney(amount, currency, { base: currency })}{' '}
        {direction === 'in' ? 'from' : 'to'} {name}
      </p>

      <div className="mt-5 w-full rounded-card border border-line bg-sunken px-4 py-3">
        <p className="text-[0.75rem] text-ink-muted">
          {remaining > 0 ? 'Remaining balance' : 'Balance'}
        </p>
        <p
          className={cn(
            'tnum mt-0.5 font-display text-[1.375rem] font-semibold tracking-tight',
            remaining > 0
              ? direction === 'in'
                ? 'text-receivable'
                : 'text-payable'
              : 'text-ink',
          )}
        >
          {remaining > 0 ? formatMoney(remaining, currency, { base: currency }) : 'Fully settled'}
        </p>
      </div>

      {/* The only focusable control in this state, so the modal lands on it. */}
      <Button full className="mt-5" onClick={onClose}>
        Done
      </Button>
    </div>
  );
}

function SideOption({
  active,
  tone,
  title,
  amount,
  onClick,
}: {
  active: boolean;
  tone: 'receivable' | 'payable';
  title: string;
  amount: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        'rounded-field border px-3.5 py-3 text-left',
        'transition-[border-color,background-color,box-shadow] duration-[var(--dur)] ease-[var(--ease)]',
        active
          ? tone === 'receivable'
            ? 'border-receivable bg-receivable-soft ring-1 ring-receivable/30'
            : 'border-payable bg-payable-soft ring-1 ring-payable/30'
          : 'border-line bg-sunken hover:border-line-strong',
      )}
    >
      <span className="block text-[0.8125rem] font-semibold text-ink">{title}</span>
      <span
        className={cn(
          'tnum block text-[0.8125rem]',
          active ? (tone === 'receivable' ? 'text-receivable' : 'text-payable') : 'text-ink-muted',
        )}
      >
        {amount}
      </span>
    </button>
  );
}
