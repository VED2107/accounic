'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button } from '@/components/ui/primitives';
import { PlusIcon } from '@/components/icons';
import { TransactionSheet } from '@/components/ledger/transaction-sheet';

/**
 * Opens the transaction sheet from anywhere a server component needs to offer
 * it (upgrade §11).
 *
 * It exists for the empty states. "Transactions will appear here as you record
 * them" tells a new user what is missing and why, and then leaves them to go
 * and find the way to fix it — which is the difference between an empty state
 * that explains and one that helps. This is the same shape as
 * `AddPersonButton`, which the People page has had all along.
 */
export function AddTransactionButton({
  currency,
  label = 'Add transaction',
  variant = 'primary',
}: {
  /** The workspace currency, used until a person is picked. */
  currency: string;
  label?: string;
  variant?: 'primary' | 'secondary';
}) {
  const router = useRouter();
  const [open, setOpen] = useState(false);

  return (
    <>
      <Button variant={variant} onClick={() => setOpen(true)}>
        <PlusIcon className="size-4" />
        {label}
      </Button>
      <TransactionSheet
        open={open}
        onClose={() => {
          setOpen(false);
          // The sheet refreshes on save; this covers the case where the user
          // recorded something and the page behind is an empty state that is
          // no longer true.
          router.refresh();
        }}
        currency={currency}
        mode="create"
      />
    </>
  );
}
