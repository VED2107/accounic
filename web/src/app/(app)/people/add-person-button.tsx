'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/primitives';
import { PlusIcon } from '@/components/icons';
import { PersonForm } from '@/components/ledger/person-form';

export function AddPersonButton({
  label = 'Add person',
  baseCurrency,
}: {
  label?: string;
  /** The workspace currency, which a new account defaults to (upgrade §1). */
  baseCurrency?: string;
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);

  return (
    <>
      <Button onClick={() => setOpen(true)}>
        <PlusIcon className="size-4" />
        {label}
      </Button>
      <PersonForm
        open={open}
        onClose={() => setOpen(false)}
        baseCurrency={baseCurrency}
        // Straight to the new account: the reason to add someone is almost
        // always to record something against them (context.md §36).
        onCreated={(person) => router.push(`/people/${person.id}`)}
      />
    </>
  );
}
