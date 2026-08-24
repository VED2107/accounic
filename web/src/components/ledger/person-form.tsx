'use client';

import { useActionState, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Modal } from '@/components/ui/modal';
import { ErrorNote, Field, Input, Textarea, cn } from '@/components/ui/primitives';
import { SubmitRow } from '@/components/ledger/transaction-sheet';
import { CurrencySelect } from '@/components/ledger/currency-select';
import {
  ConversionNote,
  useRate,
} from '@/components/ledger/conversion';
import { AmountInput } from '@/components/ledger/amount-input';
import { useToast } from '@/components/ui/toast';
import { createPerson, updatePerson } from '@/lib/actions';
import { FALLBACK_CURRENCY, normaliseCode } from '@/lib/currencies';
import { parseAmountToMinor } from '@/lib/money';
import type { ActionResult, OpeningDirection, PartyType, Person } from '@/lib/types';

/**
 * Create / edit a person or business (context.md §5; upgrade §1, §3, §4).
 *
 * Three things beyond a name and a phone number:
 *
 *   * **Currency.** Each account runs in its own, defaulting to the workspace's
 *     base currency. Existing people have none stored, which means exactly that
 *     default — so nothing changes for anyone who only ever uses one currency.
 *   * **Opening balance.** The point of it is that a user with real-world
 *     balances can start from where they actually are rather than inventing a
 *     transaction dated today to fake it.
 *   * **Restatement.** Changing the currency of an account that already holds
 *     entries has to restate them, which moves numbers the user has seen. It is
 *     therefore refused once and explained, rather than done quietly.
 */
export function PersonForm({
  open,
  onClose,
  person,
  baseCurrency = FALLBACK_CURRENCY,
  onCreated,
}: {
  open: boolean;
  onClose: () => void;
  person?: Person;
  baseCurrency?: string;
  onCreated?: (person: Person) => void;
}) {
  const router = useRouter();
  const toast = useToast();
  const isEdit = Boolean(person);

  const originalCurrency = normaliseCode(person?.currency ?? baseCurrency) || FALLBACK_CURRENCY;

  const [type, setType] = useState<PartyType>(person?.type ?? 'person');
  const [currency, setCurrency] = useState(originalCurrency);
  const [direction, setDirection] = useState<OpeningDirection>('none');
  const [openingCurrency, setOpeningCurrency] = useState(originalCurrency);
  const [openingAmount, setOpeningAmount] = useState<number | null>(null);

  const action = person
    ? updatePerson.bind(null, person.id)
    : (createPerson as (
        prev: ActionResult<Person> | null,
        formData: FormData,
      ) => Promise<ActionResult<Person>>);

  const [state, formAction] = useActionState<ActionResult<Person> | null, FormData>(action, null);

  useEffect(() => {
    if (!open) return;
    setType(person?.type ?? 'person');
    setCurrency(originalCurrency);
    setOpeningCurrency(originalCurrency);
    setDirection('none');
    setOpeningAmount(null);
  }, [open, person, originalCurrency]);

  // The opening balance may be stated in a currency other than the account's —
  // "I know I owe him ₹5,000" on a dirham account is the case this exists for.
  const openingRate = useRate(openingCurrency, currency);

  // And changing an existing account's currency needs a rate to restate it at.
  const currencyChanged = isEdit && currency !== originalCurrency;
  const restateRate = useRate(currencyChanged ? originalCurrency : '', currency);

  // `onCreated` is an inline arrow at most call sites, so it is a new function
  // on every render. Keyed on that alone this effect would re-run — and
  // re-navigate — long after the person was created. The result is handled once,
  // by identity.
  const handled = useRef<ActionResult<Person> | null>(null);

  useEffect(() => {
    if (!state?.ok || handled.current === state) return;
    handled.current = state;

    onClose();
    if (!isEdit && onCreated) onCreated(state.data);
    router.refresh();
    toast.show({
      tone: 'success',
      title: isEdit ? 'Details saved' : `${state.data.name} added`,
    });
  }, [state, onClose, onCreated, isEdit, router, toast]);

  const fieldError = (field: string) =>
    state && !state.ok && state.field === field ? state.error : undefined;

  // The database refuses the first attempt at a restatement and says why. That
  // refusal is the confirmation step: the same form comes back with the
  // consequence stated and a box to tick, and nothing has been written.
  const needsRestateConfirmation =
    Boolean(state && !state.ok && /restates them/i.test(state.error));

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={isEdit ? 'Edit details' : 'Add person or business'}
      size="lg"
    >
      <form action={formAction} className="space-y-5" noValidate>
        {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}

        <Field label="Name" htmlFor="name" error={fieldError('name')}>
          <Input
            id="name"
            name="name"
            data-autofocus="true"
            defaultValue={person?.name ?? ''}
            placeholder="Rahul Traders"
            maxLength={120}
            required
          />
        </Field>

        <div className="grid gap-4 sm:grid-cols-2">
          <fieldset className="space-y-1.5">
            <legend className="text-sm font-medium text-ink">Type</legend>
            <div className="grid grid-cols-2 gap-2">
              {(['person', 'business'] as const).map((option) => (
                <button
                  key={option}
                  type="button"
                  onClick={() => setType(option)}
                  aria-pressed={type === option}
                  className={cn(
                    'rounded-lg border px-3.5 py-2.5 text-sm font-medium capitalize transition',
                    type === option
                      ? 'border-accent bg-accent-soft text-accent'
                      : 'border-line-strong bg-surface text-ink-muted hover:bg-sunken hover:text-ink',
                  )}
                >
                  {option}
                </button>
              ))}
            </div>
            <input type="hidden" name="type" value={type} />
          </fieldset>

          <CurrencySelect
            name="currency"
            value={currency}
            onChange={(next) => {
              setCurrency(next);
              // The opening balance follows the account currency until the user
              // says otherwise, which is what they mean nine times in ten.
              if (direction === 'none' || openingAmount === null) setOpeningCurrency(next);
            }}
            hint={currency === baseCurrency ? 'Same as your workspace' : undefined}
            error={fieldError('currency')}
          />
        </div>

        {currencyChanged ? (
          <div className="rounded-lg border border-line bg-sunken px-3.5 py-3 text-[0.8125rem] text-ink-muted">
            <p className="font-medium text-ink">
              This account is recorded in {originalCurrency}.
            </p>
            <p className="mt-1">
              Changing it to {currency} restates every entry at today’s rate. The original
              amount, currency and rate stay on every row, so nothing is lost — but the
              balances you have seen will be shown in {currency} from now on.
            </p>
            {restateRate.rate ? (
              <p className="mt-1.5 text-ink-faint">{restateRate.rate.provenance}</p>
            ) : null}
            {!restateRate.loading && !restateRate.rate ? (
              <p className="mt-1.5 font-medium text-payable" role="alert">
                No {originalCurrency} → {currency} rate is available, so this account cannot
                be restated right now. Nothing has been changed.
              </p>
            ) : null}

            {needsRestateConfirmation ? (
              <label className="mt-3 flex items-start gap-2 text-ink">
                <input
                  type="checkbox"
                  name="restate_confirmed"
                  value="on"
                  defaultChecked
                  className="mt-0.5 size-4 rounded border-line-strong"
                />
                <span>Yes, restate this account into {currency} at that rate.</span>
              </label>
            ) : null}
            <input type="hidden" name="restate_rate_e9" value={restateRate.rate?.rate_e9 ?? ''} />
          </div>
        ) : null}

        {!isEdit ? (
          <fieldset className="space-y-3 rounded-card border border-line bg-sunken/60 p-4">
            <legend className="px-1 text-sm font-medium text-ink">Existing balance</legend>
            <p className="text-[0.8125rem] text-ink-muted">
              Already have an amount to settle with this person? Start from it rather than
              recording a transaction that never happened.
            </p>

            <div className="grid gap-2 sm:grid-cols-3">
              {(
                [
                  ['none', 'No opening balance'],
                  ['i_owe_them', 'I owe them'],
                  ['they_owe_me', 'They owe me'],
                ] as const
              ).map(([option, label]) => (
                <button
                  key={option}
                  type="button"
                  onClick={() => setDirection(option)}
                  aria-pressed={direction === option}
                  className={cn(
                    'rounded-lg border px-3 py-2.5 text-[0.8125rem] font-medium transition',
                    direction === option
                      ? option === 'i_owe_them'
                        ? 'border-payable bg-payable-soft text-payable'
                        : option === 'they_owe_me'
                          ? 'border-receivable bg-receivable-soft text-receivable'
                          : 'border-accent bg-accent-soft text-accent'
                      : 'border-line-strong bg-surface text-ink-muted hover:bg-sunken hover:text-ink',
                  )}
                >
                  {label}
                </button>
              ))}
            </div>
            <input type="hidden" name="opening_direction" value={direction} />

            {direction !== 'none' ? (
              <div className="space-y-3">
                <div className="grid gap-4 sm:grid-cols-[1fr_auto] sm:items-end">
                  <AmountInput
                    name="opening_amount"
                    label="Opening amount"
                    currency={openingCurrency}
                    error={fieldError('opening_amount')}
                    onValidChange={setOpeningAmount}
                  />
                  <CurrencySelect
                    name="opening_currency"
                    label="In"
                    value={openingCurrency}
                    onChange={setOpeningCurrency}
                    className="sm:w-56"
                  />
                </div>

                <ConversionNote
                  amountMinor={openingAmount}
                  from={openingCurrency}
                  to={currency}
                  state={openingRate}
                />
                <input
                  type="hidden"
                  name="opening_rate_e9"
                  value={openingRate.rate?.rate_e9 ?? ''}
                />

                <p className="text-[0.75rem] text-ink-faint">
                  Recorded as an opening balance dated to when this account starts, not as a
                  transaction today.
                </p>
              </div>
            ) : null}
          </fieldset>
        ) : null}

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Phone" htmlFor="phone" hint="Optional" error={fieldError('phone')}>
            <Input
              id="phone"
              name="phone"
              type="tel"
              inputMode="tel"
              defaultValue={person?.phone ?? ''}
              placeholder="+91 98200 11223"
              maxLength={32}
            />
          </Field>
          <Field label="Email" htmlFor="email" hint="Optional" error={fieldError('email')}>
            <Input
              id="email"
              name="email"
              type="email"
              defaultValue={person?.email ?? ''}
              placeholder="accounts@example.com"
            />
          </Field>
        </div>

        <Field label="Address" htmlFor="address" hint="Optional" error={fieldError('address')}>
          <Input
            id="address"
            name="address"
            defaultValue={person?.address ?? ''}
            maxLength={500}
          />
        </Field>

        <Field label="Notes" htmlFor="notes" hint="Optional" error={fieldError('notes')}>
          <Textarea
            id="notes"
            name="notes"
            defaultValue={person?.notes ?? ''}
            maxLength={2000}
            placeholder="Payment terms, reference numbers, anything worth remembering."
          />
        </Field>

        <SubmitRow
          label={
            needsRestateConfirmation
              ? `Restate into ${currency}`
              : isEdit
                ? 'Save changes'
                : 'Add person'
          }
          onCancel={onClose}
          disabled={
            (direction !== 'none' && openingAmount === null && !isEdit) ||
            (currencyChanged && needsRestateConfirmation && !restateRate.rate)
          }
        />
      </form>
    </Modal>
  );
}

/** Parse helper kept local: the form only ever needs it for the disabled state. */
export function looksLikeAmount(text: string, currency: string): boolean {
  return parseAmountToMinor(text, currency) !== null;
}
