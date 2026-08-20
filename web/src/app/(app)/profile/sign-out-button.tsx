'use client';

import { useFormStatus } from 'react-dom';
import { signOut } from '@/lib/actions';
import { Button, Spinner } from '@/components/ui/primitives';

/**
 * Sign out.
 *
 * Submitted as a form action rather than called from an event handler: the
 * action ends in `redirect()`, which throws a control-flow signal that React
 * only handles when it owns the call. Invoking it from onClick discards that
 * signal and the user stays on the page with a half-cleared session.
 */
export function SignOutButton() {
  return (
    <form action={signOut}>
      <SubmitButton />
    </form>
  );
}

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" variant="secondary" disabled={pending}>
      {pending ? <Spinner /> : null}
      {pending ? 'Signing out…' : 'Sign out'}
    </Button>
  );
}
