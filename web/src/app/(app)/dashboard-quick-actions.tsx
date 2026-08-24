'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { ActivityIcon, PersonPlusIcon, PlusIcon, SearchIcon } from '@/components/icons';
import { cn } from '@/components/ui/primitives';
import { PersonForm } from '@/components/ledger/person-form';
import { TransactionSheet } from '@/components/ledger/transaction-sheet';
import { QuickSearch } from '@/components/shell/quick-search';

/**
 * The four things people actually come here to do (context.md §13).
 *
 * Every one of them opens in place — nothing on this card navigates away except
 * the one that is a destination. The keyboard shortcuts are printed on the tiles
 * because that is how anyone learns they exist.
 */
export function QuickActions({ currency }: { currency: string }) {
  const router = useRouter();
  const [sheet, setSheet] = useState<'txn' | 'person' | 'search' | null>(null);

  return (
    <>
      <div className="grid grid-cols-2 gap-2 p-4 sm:grid-cols-4 lg:grid-cols-2">
        <Action
          icon={<PlusIcon className="size-[1.125rem]" />}
          label="Add transaction"
          hint="N"
          onClick={() => setSheet('txn')}
        />
        <Action
          icon={<PersonPlusIcon className="size-[1.125rem]" />}
          label="Add person"
          onClick={() => setSheet('person')}
        />
        <Action
          icon={<SearchIcon className="size-[1.125rem]" />}
          label="Search"
          hint="⌘K"
          onClick={() => setSheet('search')}
        />
        <Action
          icon={<ActivityIcon className="size-[1.125rem]" />}
          label="All activity"
          onClick={() => router.push('/activity')}
        />
      </div>

      <TransactionSheet
        open={sheet === 'txn'}
        onClose={() => setSheet(null)}
        currency={currency}
        mode="create"
      />
      <PersonForm
        open={sheet === 'person'}
        onClose={() => setSheet(null)}
        baseCurrency={currency}
        onCreated={(person) => router.push(`/people/${person.id}`)}
      />
      <QuickSearch open={sheet === 'search'} onClose={() => setSheet(null)} currency={currency} />
    </>
  );
}

function Action({
  icon,
  label,
  hint,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  hint?: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        'group flex flex-col items-start gap-2 rounded-field border border-line bg-sunken px-3 py-3 text-left',
        'transition-[border-color,background-color,transform] duration-[var(--dur)] ease-[var(--ease)]',
        'hover:border-line-strong hover:bg-surface active:scale-[0.985] motion-reduce:active:scale-100',
      )}
    >
      <span className="flex w-full items-center justify-between">
        <span className="grid size-8 place-items-center rounded-lg border border-line bg-surface text-ink-muted transition-colors duration-[var(--dur)] group-hover:text-accent">
          {icon}
        </span>
        {hint ? (
          <kbd className="rounded border border-line px-1.5 py-0.5 text-[0.625rem] font-medium text-ink-faint">
            {hint}
          </kbd>
        ) : null}
      </span>
      <span className="text-[0.8125rem] font-medium text-ink">{label}</span>
    </button>
  );
}
