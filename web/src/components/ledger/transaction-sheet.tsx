'use client';

import { useActionState, useEffect, useRef, useState } from 'react';
import { useFormStatus } from 'react-dom';
import { useRouter } from 'next/navigation';
import { Modal } from '@/components/ui/modal';
import { Button, ErrorNote, Field, Input, Spinner, Textarea, cn } from '@/components/ui/primitives';
import { AmountInput } from '@/components/ledger/amount-input';
import { PersonPicker, type PickedPerson } from '@/components/ledger/person-picker';
import { ArrowDownIcon, ArrowUpIcon } from '@/components/icons';
import { useToast } from '@/components/ui/toast';
import { CurrencySelect } from '@/components/ledger/currency-select';
import { ConversionFields, ConversionNote, useRate } from '@/components/ledger/conversion';
import { createTransaction, updateTransaction } from '@/lib/actions';
import { minorToInput } from '@/lib/money';
import { FALLBACK_CURRENCY, normaliseCode } from '@/lib/currencies';
import { TYPE_FOR_FLOW, isReceivable, txnEffect, txnMeaning } from '@/lib/direction';
import { todayIso } from '@/lib/dates';
import type { ActionResult, TxnType } from '@/lib/types';

interface EditableTransaction {
  id: string;
  type: TxnType;
  amount_minor: number;
  transaction_date: string;
  description: string | null;
  /** Present when the entry was made in another currency (upgrade §2). */
  entered_amount_minor?: number | null;
  entered_currency?: string | null;
}

/**
 * Fast transaction entry (context.md §14).
 *
 * Who → type → amount → date → note → save. Nothing else, in that order,
 * because that is the order a person thinks about a transaction. The sheet
 * closes and the affected screens refresh from the server response, so the
 * balance is correct rather than merely optimistic.
 */
export function TransactionSheet({
  open,
  onClose,
  currency,
  mode,
  person,
  transaction,
  defaultType,
}: {
  open: boolean;
  onClose: () => void;
  currency: string;
  mode: 'create' | 'edit';
  person?: PickedPerson;
  transaction?: EditableTransaction;
  defaultType?: TxnType;
}) {
  const router = useRouter();
  const toast = useToast();
  const [picked, setPicked] = useState<PickedPerson | null>(person ?? null);
  const [type, setType] = useState<TxnType>(defaultType ?? transaction?.type ?? 'credit');

  // What this entry will be RECORDED in: the person's ledger currency, not the
  // workspace's. `currency` is the fallback for the moment before anyone has
  // been picked.
  const accountCurrency =
    normaliseCode(picked?.currency ?? person?.currency ?? currency) || FALLBACK_CURRENCY;

  // What the amount field starts out in: the person's own default currency.
  // For almost everyone this is the same string as `accountCurrency`. It differs
  // for a person who has changed currency — their history stays denominated in
  // what it was entered in, and new entries start in the new one, which is the
  // whole point of the v1.1.1 correction.
  const personDefaultCurrency =
    normaliseCode(
      picked?.default_currency ?? person?.default_currency ?? accountCurrency,
    ) || accountCurrency;

  // What the user is typing in. Defaults to the person's currency, and is
  // offered as a choice because the common real case — "I gave Ahmed ₹1,000"
  // against a dirham account — is exactly the one where they differ.
  const [entryCurrency, setEntryCurrency] = useState(personDefaultCurrency);
  const [amountMinor, setAmountMinor] = useState<number | null>(null);
  const rate = useRate(entryCurrency, accountCurrency);

  const action =
    mode === 'edit' && person
      ? updateTransaction.bind(null, person.id)
      : (createTransaction as (
          prev: ActionResult<unknown> | null,
          formData: FormData,
        ) => Promise<ActionResult<unknown>>);

  const [state, formAction] = useActionState<ActionResult<unknown> | null, FormData>(action, null);

  useEffect(() => {
    if (!open) return;
    setPicked(person ?? null);
    setType(defaultType ?? transaction?.type ?? 'credit');
    setAmountMinor(null);
  }, [open, person, transaction, defaultType]);

  // Following the person keeps the ordinary case free of decisions: pick a
  // dirham person and you are typing dirhams until you say otherwise. Editing an
  // existing row starts from what that row was actually entered in.
  useEffect(() => {
    setEntryCurrency(normaliseCode(transaction?.entered_currency ?? personDefaultCurrency));
  }, [personDefaultCurrency, transaction]);

  // `state` from useActionState stays `ok` for the life of the component, so an
  // effect keyed on it alone fires again every time anything else in this
  // component changes — reopening the sheet, or flipping credit/debit, would
  // each announce a save that never happened. The result object is handled
  // exactly once, by identity.
  const handled = useRef<ActionResult<unknown> | null>(null);

  useEffect(() => {
    if (!state?.ok || handled.current === state) return;
    handled.current = state;

    onClose();
    // The balance on the page behind updates from the server rather than
    // optimistically — an accounting figure is never guessed at (context.md §7).
    router.refresh();
    toast.show({
      tone: 'success',
      title: mode === 'edit' ? 'Transaction updated' : 'Transaction recorded',
      body:
        mode === 'edit'
          ? 'The balance has been recalculated.'
          : isReceivable(type)
            ? 'Added to what you are owed.'
            : 'Added to what you owe.',
    });
  }, [state, onClose, router, toast, mode, type]);

  const fieldError = (field: string) =>
    state && !state.ok && state.field === field ? state.error : undefined;

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={mode === 'edit' ? 'Edit transaction' : 'Add transaction'}
      description={
        mode === 'edit'
          ? 'Corrections are checked against anything already settled.'
          : undefined
      }
    >
      <form action={formAction} className="space-y-5" noValidate>
        {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}

        {mode === 'edit' && transaction ? (
          <input type="hidden" name="transaction_id" value={transaction.id} />
        ) : (
          <>
            <PersonPicker value={picked} onChange={setPicked} currency={currency} />
            <input type="hidden" name="person_id" value={picked?.id ?? ''} />
          </>
        )}

        <TypeToggle value={type} onChange={setType} />
        <input type="hidden" name="type" value={type} />

        <div className="grid gap-4 sm:grid-cols-[1fr_auto] sm:items-end">
          <AmountInput
            currency={entryCurrency}
            autoFocus={mode === 'edit' || Boolean(person)}
            defaultValue={
              transaction
                ? minorToInput(
                    transaction.entered_amount_minor ?? transaction.amount_minor,
                    transaction.entered_currency ?? accountCurrency,
                  )
                : ''
            }
            error={fieldError('amount')}
            onValidChange={setAmountMinor}
          />
          <CurrencySelect
            name="entry_currency_visible"
            label="In"
            value={entryCurrency}
            onChange={setEntryCurrency}
            hint={entryCurrency === accountCurrency ? 'Account currency' : undefined}
            className="sm:w-56"
          />
        </div>

        <ConversionNote
          amountMinor={amountMinor}
          from={entryCurrency}
          to={accountCurrency}
          state={rate}
        />
        <ConversionFields
          entryCurrency={entryCurrency}
          accountCurrency={accountCurrency}
          state={rate}
        />

        <div className="grid gap-4 sm:grid-cols-2">
          <Field label="Date" htmlFor="date" error={fieldError('date')}>
            <Input
              id="date"
              name="date"
              type="date"
              max={todayIso()}
              defaultValue={transaction?.transaction_date ?? todayIso()}
              required
            />
          </Field>
          <Field label="Note" htmlFor="description" hint="Optional">
            <Input
              id="description"
              name="description"
              defaultValue={transaction?.description ?? ''}
              placeholder="Invoice #102"
              maxLength={500}
            />
          </Field>
        </div>

        <SubmitRow
          disabled={(mode === 'create' && !picked) || rate.unavailable || rate.loading}
          label={mode === 'edit' ? 'Save changes' : 'Save transaction'}
          onCancel={onClose}
        />
      </form>
    </Modal>
  );
}

/**
 * Credit / Debit in the user's language, not accounting's (context.md §8).
 *
 * Credit is money arriving from the person, which leaves the owner owing it
 * back; debit is money going the other way. The plain-English line under each
 * option is what stops the two being mixed up, and the colour agrees with it:
 * red for what you owe, green for what you are owed. See lib/direction.ts.
 */
function TypeToggle({ value, onChange }: { value: TxnType; onChange: (next: TxnType) => void }) {
  return (
    <fieldset className="space-y-1.5">
      <legend className="mb-1.5 text-[0.8125rem] font-medium text-ink-muted">Type</legend>
      <div className="grid grid-cols-2 gap-2">
        <TypeOption
          active={value === TYPE_FOR_FLOW.person_to_owner}
          onClick={() => onChange(TYPE_FOR_FLOW.person_to_owner)}
          tone="payable"
          icon={<ArrowDownIcon className="size-4" />}
          title="Credit"
          subtitle={txnMeaning(TYPE_FOR_FLOW.person_to_owner)}
          effect={txnEffect(TYPE_FOR_FLOW.person_to_owner)}
        />
        <TypeOption
          active={value === TYPE_FOR_FLOW.owner_to_person}
          onClick={() => onChange(TYPE_FOR_FLOW.owner_to_person)}
          tone="receivable"
          icon={<ArrowUpIcon className="size-4" />}
          title="Debit"
          subtitle={txnMeaning(TYPE_FOR_FLOW.owner_to_person)}
          effect={txnEffect(TYPE_FOR_FLOW.owner_to_person)}
        />
      </div>
    </fieldset>
  );
}

function TypeOption({
  active,
  onClick,
  tone,
  icon,
  title,
  subtitle,
  effect,
}: {
  active: boolean;
  onClick: () => void;
  tone: 'receivable' | 'payable';
  icon: React.ReactNode;
  title: string;
  subtitle: string;
  effect: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        'flex flex-col items-start gap-1 rounded-field border px-3.5 py-3 text-left',
        'transition-[border-color,background-color,box-shadow] duration-[var(--dur)] ease-[var(--ease)]',
        active
          ? tone === 'receivable'
            ? 'border-receivable bg-receivable-soft ring-1 ring-receivable/30'
            : 'border-payable bg-payable-soft ring-1 ring-payable/30'
          : 'border-line bg-sunken hover:border-line-strong',
      )}
    >
      <span
        className={cn(
          'flex items-center gap-1.5 text-sm font-semibold',
          active ? (tone === 'receivable' ? 'text-receivable' : 'text-payable') : 'text-ink',
        )}
      >
        {icon}
        {title}
      </span>
      <span className="text-[0.75rem] text-ink-muted">{subtitle}</span>
      <span
        className={cn(
          'text-[0.6875rem] font-medium',
          tone === 'receivable' ? 'text-receivable' : 'text-payable',
        )}
      >
        {effect}
      </span>
    </button>
  );
}

export function SubmitRow({
  label,
  onCancel,
  disabled = false,
  tone = 'primary',
}: {
  label: string;
  onCancel: () => void;
  disabled?: boolean;
  tone?: 'primary' | 'receivable' | 'payable';
}) {
  const { pending } = useFormStatus();
  return (
    <div className="flex gap-2 pt-1">
      <Button type="button" variant="secondary" onClick={onCancel} disabled={pending}>
        Cancel
      </Button>
      <Button type="submit" variant={tone} full disabled={pending || disabled}>
        {pending ? <Spinner /> : null}
        {pending ? 'Saving…' : label}
      </Button>
    </div>
  );
}
