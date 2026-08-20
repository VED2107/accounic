'use client';

import { useActionState, useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Modal } from '@/components/ui/modal';
import { ErrorNote, Field, Input, Textarea, cn } from '@/components/ui/primitives';
import { SubmitRow } from '@/components/ledger/transaction-sheet';
import { useToast } from '@/components/ui/toast';
import { createPerson, updatePerson } from '@/lib/actions';
import type { ActionResult, PartyType, Person } from '@/lib/types';

/**
 * Create / edit a person or business (context.md §5).
 *
 * The type is a two-way toggle rather than a dropdown of accounting categories:
 * the spec asks for generic terminology, and everything past "is this a person
 * or a company" is a label the user does not need.
 */
export function PersonForm({
  open,
  onClose,
  person,
  onCreated,
}: {
  open: boolean;
  onClose: () => void;
  person?: Person;
  onCreated?: (person: Person) => void;
}) {
  const router = useRouter();
  const toast = useToast();
  const isEdit = Boolean(person);
  const [type, setType] = useState<PartyType>(person?.type ?? 'person');

  const action = person
    ? updatePerson.bind(null, person.id)
    : (createPerson as (
        prev: ActionResult<Person> | null,
        formData: FormData,
      ) => Promise<ActionResult<Person>>);

  const [state, formAction] = useActionState<ActionResult<Person> | null, FormData>(action, null);

  useEffect(() => {
    if (open) setType(person?.type ?? 'person');
  }, [open, person]);

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

        <SubmitRow label={isEdit ? 'Save changes' : 'Add person'} onCancel={onClose} />
      </form>
    </Modal>
  );
}
