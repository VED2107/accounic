'use client';

import { useActionState, useEffect } from 'react';
import { useFormStatus } from 'react-dom';
import { useRouter } from 'next/navigation';
import { signIn } from '@/lib/actions';
import { Button, Card, ErrorNote, Field, Input, Spinner } from '@/components/ui/primitives';
import type { ActionResult } from '@/lib/types';

export function LoginForm({ next }: { next?: string }) {
  const router = useRouter();
  const [state, formAction] = useActionState<ActionResult<null> | null, FormData>(signIn, null);

  useEffect(() => {
    if (state?.ok) {
      // A full refresh so the server components re-render with the new session
      // cookie that the action just set.
      router.replace(next && next.startsWith('/') ? next : '/');
      router.refresh();
    }
  }, [state, router, next]);

  return (
    <Card className="bg-raised p-6 shadow-[var(--shadow-raised)]">
      <form action={formAction} className="space-y-4" noValidate>
        {state && !state.ok ? <ErrorNote>{state.error}</ErrorNote> : null}

        <Field
          label="Email"
          htmlFor="email"
          error={state && !state.ok && state.field === 'email' ? state.error : undefined}
        >
          <Input
            id="email"
            name="email"
            type="email"
            autoComplete="username"
            inputMode="email"
            autoFocus
            required
            placeholder="you@example.com"
          />
        </Field>

        <Field
          label="Password"
          htmlFor="password"
          error={state && !state.ok && state.field === 'password' ? state.error : undefined}
        >
          <Input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            required
            placeholder="••••••••••"
          />
        </Field>

        <SubmitButton />
      </form>
    </Card>
  );
}

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" size="lg" full disabled={pending}>
      {pending ? <Spinner /> : null}
      {pending ? 'Signing in…' : 'Sign in'}
    </Button>
  );
}
