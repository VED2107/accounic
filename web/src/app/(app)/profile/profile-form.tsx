'use client';

import { useActionState, useEffect, useState } from 'react';
import { useFormStatus } from 'react-dom';
import { useRouter } from 'next/navigation';
import { updateProfile } from '@/lib/actions';
import { Button, ErrorNote, Field, Input, Select, Spinner, SuccessNote } from '@/components/ui/primitives';
import { useToast } from '@/components/ui/toast';
import type { ActionResult, Me } from '@/lib/types';

const CURRENCIES = ['INR', 'USD', 'EUR', 'GBP', 'AED', 'AUD', 'CAD', 'SGD'];

export function ProfileForm({ me }: { me: Me }) {
  const router = useRouter();
  const toast = useToast();
  const [state, formAction] = useActionState<ActionResult<null> | null, FormData>(
    updateProfile,
    null,
  );
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (!state?.ok) return;
    setSaved(true);
    router.refresh();
    toast.show({ tone: 'success', title: 'Details saved' });
    const timer = window.setTimeout(() => setSaved(false), 3000);
    return () => window.clearTimeout(timer);
  }, [state, router, toast]);

  const fieldError = (field: string) =>
    state && !state.ok && state.field === field ? state.error : undefined;

  return (
    <form action={formAction} className="space-y-4" noValidate>
      {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}
      {saved ? <SuccessNote>Your details are saved.</SuccessNote> : null}

      <p className="text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
        Personal
      </p>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field label="Name" htmlFor="name" error={fieldError('name')}>
          <Input id="name" name="name" defaultValue={me.name} maxLength={120} required />
        </Field>
        <Field label="Phone" htmlFor="phone" hint="Optional" error={fieldError('phone')}>
          <Input
            id="phone"
            name="phone"
            type="tel"
            inputMode="tel"
            defaultValue={me.phone ?? ''}
            maxLength={32}
          />
        </Field>
      </div>

      <p className="pt-1 text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
        Business &amp; preferences
      </p>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          label="Business name"
          htmlFor="business_name"
          hint="Optional"
          error={fieldError('business_name')}
        >
          <Input
            id="business_name"
            name="business_name"
            defaultValue={me.business_name ?? ''}
            maxLength={120}
          />
        </Field>
        <Field
          label="Currency"
          htmlFor="currency"
          hint="Used everywhere amounts are shown"
          error={fieldError('currency')}
        >
          <Select id="currency" name="currency" defaultValue={me.currency}>
            {(CURRENCIES.includes(me.currency) ? CURRENCIES : [me.currency, ...CURRENCIES]).map(
              (code) => (
                <option key={code} value={code}>
                  {code}
                </option>
              ),
            )}
          </Select>
        </Field>
      </div>

      <SaveButton />
    </form>
  );
}

function SaveButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" disabled={pending}>
      {pending ? <Spinner /> : null}
      {pending ? 'Saving…' : 'Save details'}
    </Button>
  );
}
