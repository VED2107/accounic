'use client';

import { useActionState, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Modal } from '@/components/ui/modal';
import {
  ErrorNote,
  Field,
  FormSection,
  FormSections,
  Input,
  cn,
} from '@/components/ui/primitives';
import { AmountInput } from '@/components/ledger/amount-input';
import { PersonPicker, type PickedPerson } from '@/components/ledger/person-picker';
import { CurrencySelect } from '@/components/ledger/currency-select';
import { ConversionFields, ConversionPanel, useRate } from '@/components/ledger/conversion';
import { SubmitRow } from '@/components/ledger/transaction-sheet';
import { ArrowRightIcon } from '@/components/icons';
import { useToast } from '@/components/ui/toast';
import { createTransfer } from '@/lib/actions';
import { convertMinor, FALLBACK_CURRENCY, normaliseCode } from '@/lib/currencies';
import { formatMoney } from '@/lib/money';
import { todayIso } from '@/lib/dates';
import type { ActionResult } from '@/lib/types';
import { DateField } from '@/components/ui/date-picker';

/**
 * Move money from one person to another (upgrade §46).
 *
 * The sheet is deliberately shaped like the sentence a user would say — from
 * whom, to whom, how much — and it never asks for a direction, because a
 * transfer has one by construction: it leaves the first account and arrives in
 * the second.
 *
 * Two conversions can be involved and usually neither is:
 *
 *     what you typed  →  what leaves the source  →  what reaches the destination
 *
 * Each panel appears only when its two currencies differ, so a single-currency
 * transfer — which is nearly all of them — is four fields and a button.
 *
 * The client never computes a figure that gets stored. Amounts and rates travel;
 * the database derives both converted amounts, exactly as it does for every
 * other money RPC (context.md §7). The one exception is "what actually
 * arrived", which is not derived from anything.
 */
export function TransferSheet({
  open,
  onClose,
  baseCurrency,
  from,
}: {
  open: boolean;
  onClose: () => void;
  /** The workspace currency — the fallback before anyone has been picked. */
  baseCurrency: string;
  /** Pre-selected source, when opened from a person's page. */
  from?: PickedPerson;
}) {
  const router = useRouter();
  const toast = useToast();

  const [source, setSource] = useState<PickedPerson | null>(from ?? null);
  const [destination, setDestination] = useState<PickedPerson | null>(null);
  const [amountMinor, setAmountMinor] = useState<number | null>(null);

  // The two ledger denominations. `currency` on a picked person is their LEDGER
  // currency — what their stored figures are in — which is what a transfer
  // moves, so it is the right one here and `default_currency` is not.
  const fromCurrency =
    normaliseCode(source?.currency ?? '') || normaliseCode(baseCurrency) || FALLBACK_CURRENCY;
  const toCurrency =
    normaliseCode(destination?.currency ?? '') || fromCurrency;

  // What the user types in. Follows the source account, because that is the
  // money actually leaving; it is offered as a choice for the case where it is
  // not (a rupee figure moved out of a dirham account).
  const [entryCurrency, setEntryCurrency] = useState(fromCurrency);
  useEffect(() => {
    setEntryCurrency(fromCurrency);
  }, [fromCurrency]);

  const entryRate = useRate(entryCurrency, fromCurrency);
  const crossRate = useRate(fromCurrency, toCurrency);

  /**
   * One token per opened sheet, so a double-submitted form moves the money once.
   *
   * Minted here rather than on the server: the point is that the SECOND request
   * carries the same value as the first, which only the client can arrange. The
   * database refuses to create a second transfer for a token it has already
   * seen and returns the first one instead.
   */
  const [token, setToken] = useState(() => crypto.randomUUID());

  const [state, formAction] = useActionState<ActionResult<unknown> | null, FormData>(
    createTransfer as (
      prev: ActionResult<unknown> | null,
      formData: FormData,
    ) => Promise<ActionResult<unknown>>,
    null,
  );

  useEffect(() => {
    if (!open) return;
    setSource(from ?? null);
    setDestination(null);
    setAmountMinor(null);
    setToken(crypto.randomUUID());
  }, [open, from]);

  // `state` stays `ok` for the life of the component, so the success effect is
  // keyed on the result's identity rather than on its truth — otherwise picking
  // a different person after a save would announce the save a second time.
  const handled = useRef<ActionResult<unknown> | null>(null);

  useEffect(() => {
    if (!state?.ok || handled.current === state) return;
    handled.current = state;

    onClose();
    router.refresh();
    toast.show({
      tone: 'success',
      title: 'Transfer recorded',
      body: 'Both accounts have been updated.',
    });
  }, [state, onClose, router, toast]);

  const fieldError = (field: string) =>
    state && !state.ok && state.field === field ? state.error : undefined;

  const samePerson = Boolean(source && destination && source.id === destination.id);

  // What leaves the source, previewed. The stored figure is the database's.
  const sourceMinor = useMemo(() => {
    if (amountMinor === null) return null;
    if (entryCurrency === fromCurrency) return amountMinor;
    return convertMinor(amountMinor, entryCurrency, fromCurrency, entryRate.rate?.rate_e9 ?? null);
  }, [amountMinor, entryCurrency, fromCurrency, entryRate.rate]);

  const blocked =
    !source ||
    !destination ||
    samePerson ||
    (entryCurrency !== fromCurrency && (entryRate.loading || entryRate.unavailable)) ||
    (fromCurrency !== toCurrency && (crossRate.loading || crossRate.unavailable));

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Transfer money"
      description="Moves money between two of your accounts. One transaction, recorded on both."
    >
      <form action={formAction} className="space-y-5" noValidate>
        {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}

        <FormSections>
          <FormSection title="From">
            <PersonPicker value={source} onChange={setSource} currency={baseCurrency} />
            <input type="hidden" name="from_person_id" value={source?.id ?? ''} />
          </FormSection>

          <FormSection title="To" aside={fieldError('to_person_id')}>
            <PersonPicker
              value={destination}
              onChange={setDestination}
              currency={baseCurrency}
            />
            <input type="hidden" name="to_person_id" value={destination?.id ?? ''} />
            {samePerson ? (
              <p role="alert" className="mt-2 text-[0.8125rem] font-medium text-payable">
                Money cannot be transferred to the account it came from. Choose someone else.
              </p>
            ) : null}
          </FormSection>

          {/* The sentence, before any of the arithmetic: who loses it and who
              gains it. Read once here, the two panels below are detail. */}
          {source && destination && !samePerson ? (
            <Direction
              from={source.name}
              to={destination.name}
              fromCurrency={fromCurrency}
              toCurrency={toCurrency}
            />
          ) : null}

          <FormSection
            title="Amount"
            aside={
              entryCurrency === fromCurrency ? undefined : `Leaves the account in ${fromCurrency}`
            }
          >
            <div className="grid gap-4 sm:grid-cols-[1fr_auto] sm:items-end">
              <AmountInput
                currency={entryCurrency}
                autoFocus={Boolean(from)}
                error={fieldError('amount')}
                onValidChange={setAmountMinor}
              />
              <CurrencySelect
                name="entry_currency_visible"
                label="Entered in"
                value={entryCurrency}
                onChange={setEntryCurrency}
                hint={entryCurrency === fromCurrency ? 'Source account currency' : undefined}
                className="sm:w-56"
              />
            </div>

            {/* Step one — only when the user typed in something other than the
                source account's own denomination. No "actual amount" override:
                nothing has changed hands yet at this point. */}
            <ConversionPanel
              amountMinor={amountMinor}
              from={entryCurrency}
              to={fromCurrency}
              state={entryRate}
              prefix="transfer_entry_"
              allowAmountOverride={false}
            />
            <ConversionFields
              entryCurrency={entryCurrency}
              accountCurrency={fromCurrency}
              state={entryRate}
              prefix="transfer_entry_"
            />

            {/* Step two — what reaches the other account, and the one place a
                user can say the counter handed over something else. */}
            <ConversionPanel
              amountMinor={sourceMinor}
              from={fromCurrency}
              to={toCurrency}
              state={crossRate}
            />
            <ConversionFields
              entryCurrency={fromCurrency}
              accountCurrency={toCurrency}
              state={crossRate}
            />

            {/* The two currency codes the server validates against. Sent from
                the form so the browser and the server agree about which
                denominations are in play, exactly as the transaction sheet
                sends `account_currency`. */}
            <input type="hidden" name="from_currency" value={fromCurrency} />
            <input type="hidden" name="to_currency" value={toCurrency} />
            <input type="hidden" name="entry_currency" value={entryCurrency} />
            <input type="hidden" name="client_token" value={token} />
          </FormSection>

          <FormSection title="Details">
            <div className="grid gap-4 sm:grid-cols-2">
              <Field label="Date" htmlFor="transfer-date" error={fieldError('date')}>
                <DateField
                  id="transfer-date"
                  name="date"
                  max={todayIso()}
                  defaultValue={todayIso()}
                  required
                />
              </Field>
              <Field label="Reference" htmlFor="transfer-note" hint="Optional">
                <Input
                  id="transfer-note"
                  name="note"
                  placeholder="Rent share"
                  maxLength={500}
                />
              </Field>
            </div>
          </FormSection>
        </FormSections>

        <SubmitRow disabled={blocked} label="Record transfer" onCancel={onClose} />
      </form>
    </Modal>
  );
}

/**
 * Who loses it and who gains it, stated in one line.
 *
 * The arrow does the work a "direction" toggle would otherwise have to, and it
 * cannot be set wrong: it is read from the two pickers rather than chosen.
 */
function Direction({
  from,
  to,
  fromCurrency,
  toCurrency,
}: {
  from: string;
  to: string;
  fromCurrency: string;
  toCurrency: string;
}) {
  return (
    <div className="flex flex-wrap items-center gap-2 rounded-card border border-line bg-sunken px-4 py-3">
      <Party name={from} currency={fromCurrency} tone="out" />
      <ArrowRightIcon className="size-4 shrink-0 text-ink-faint" aria-hidden />
      <Party name={to} currency={toCurrency} tone="in" />
    </div>
  );
}

function Party({
  name,
  currency,
  tone,
}: {
  name: string;
  currency: string;
  tone: 'in' | 'out';
}) {
  return (
    <span className="min-w-0">
      <span className="block truncate text-[0.875rem] font-semibold text-ink">{name}</span>
      <span
        className={cn(
          'text-[0.75rem] font-medium',
          tone === 'in' ? 'text-receivable' : 'text-payable',
        )}
      >
        {tone === 'in' ? 'receives' : 'pays'} · {currency}
      </span>
    </span>
  );
}

/**
 * The line a recorded transfer is summarised by, wherever one is shown outside
 * the timeline. Kept beside the sheet so the wording of a transfer lives in one
 * file rather than two.
 */
export function transferSummary(
  fromAmountMinor: number,
  fromCurrency: string,
  toAmountMinor: number,
  toCurrency: string,
): string {
  const left = formatMoney(fromAmountMinor, fromCurrency);
  if (normaliseCode(fromCurrency) === normaliseCode(toCurrency)) return left;
  return `${left} → ${formatMoney(toAmountMinor, toCurrency)}`;
}
