'use client';

import { useActionState, useEffect, useRef, useState } from 'react';
import { useFormStatus } from 'react-dom';
import { changeMyPassword } from '@/lib/actions';
import { Button, ErrorNote, Field, Input, Spinner, SuccessNote } from '@/components/ui/primitives';
import type { ActionResult } from '@/lib/types';

export function PasswordForm() {
  const [state, formAction] = useActionState<ActionResult<null> | null, FormData>(
    changeMyPassword,
    null,
  );
  const [changed, setChanged] = useState(false);
  const formRef = useRef<HTMLFormElement>(null);

  useEffect(() => {
    if (!state?.ok) return;
    setChanged(true);
    formRef.current?.reset();
    const timer = window.setTimeout(() => setChanged(false), 4000);
    return () => window.clearTimeout(timer);
  }, [state]);

  const fieldError = (field: string) =>
    state && !state.ok && state.field === field ? state.error : undefined;

  return (
    <form ref={formRef} action={formAction} className="space-y-4" noValidate>
      {state && !state.ok && !state.field ? <ErrorNote>{state.error}</ErrorNote> : null}
      {changed ? <SuccessNote>Your password has been changed.</SuccessNote> : null}

      <div className="grid gap-4 sm:grid-cols-2">
        <Field
          label="New password"
          htmlFor="password"
          hint="At least 10 characters"
          error={fieldError('password')}
        >
          <Input
            id="password"
            name="password"
            type="password"
            autoComplete="new-password"
            required
          />
        </Field>
        <Field label="Confirm password" htmlFor="confirm" error={fieldError('confirm')}>
          <Input
            id="confirm"
            name="confirm"
            type="password"
            autoComplete="new-password"
            required
          />
        </Field>
      </div>

      <ChangeButton />
    </form>
  );
}

function ChangeButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" variant="secondary" disabled={pending}>
      {pending ? <Spinner /> : null}
      {pending ? 'Changing…' : 'Change password'}
    </Button>
  );
}
