'use client';

import { useCallback, useEffect, useRef, useState, useTransition } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { CloseIcon, SearchIcon } from '@/components/icons';
import { SEGMENT_GROUP, Spinner, cn, segmentClass } from '@/components/ui/primitives';

const SORTS = [
  { value: 'name', label: 'Name' },
  { value: 'balance', label: 'Balance' },
  { value: 'recent', label: 'Recent' },
] as const;

const SIDES = [
  { value: 'all', label: 'All' },
  { value: 'in', label: 'Receivable' },
  { value: 'out', label: 'Payable' },
  { value: 'settled', label: 'Settled' },
] as const;

/**
 * Filter bar for the people list.
 *
 * Writes to the URL and lets the server re-render. Typing is debounced and
 * replaces history rather than pushing, so the back button still goes back to
 * the previous screen instead of walking through every keystroke.
 */
export function PeopleToolbar({
  query,
  sort,
  side,
  includeArchived,
}: {
  query: string;
  sort: string;
  side: string;
  includeArchived: boolean;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const [value, setValue] = useState(query);
  const [pending, startTransition] = useTransition();
  const firstRender = useRef(true);

  const build = useCallback(
    (overrides: { q?: string; sort?: string; side?: string; archived?: boolean }) => {
      const params = new URLSearchParams();
      const q = overrides.q ?? value;
      const nextSort = overrides.sort ?? sort;
      const nextSide = overrides.side ?? side;
      const nextArchived = overrides.archived ?? includeArchived;

      if (q.trim()) params.set('q', q.trim());
      if (nextSort !== 'name') params.set('sort', nextSort);
      if (nextSide !== 'all') params.set('side', nextSide);
      if (nextArchived) params.set('archived', '1');
      return params;
    },
    [value, sort, side, includeArchived],
  );

  const push = useCallback(
    (params: URLSearchParams) => {
      startTransition(() => {
        router.replace(params.size ? `${pathname}?${params}` : pathname, { scroll: false });
      });
    },
    [pathname, router],
  );

  useEffect(() => {
    if (firstRender.current) {
      firstRender.current = false;
      return;
    }
    const timer = window.setTimeout(() => push(build({})), 220);
    return () => window.clearTimeout(timer);
  }, [value, build, push]);

  return (
    /* Two rows, not one.

       Search, a balance filter, a sort and an archive toggle used to sit in a
       single flat row as four controls of near-identical shape — three of them
       segmented groups — which read as one long undifferentiated bar. Nothing
       said which of them changed *what you are looking at* and which changed
       *the order it is in*, so the whole bar had to be read before any of it
       could be used. Splitting search onto its own line and naming the two
       groups costs one line of height and removes the guessing. */
    <div className="space-y-2.5">
      <div className="flex flex-wrap items-center gap-2">
      <div
        className={cn(
          'flex min-w-52 flex-1 items-center gap-2 rounded-field border border-line bg-sunken px-3',
          'transition-[border-color,background-color] duration-[var(--dur)] ease-[var(--ease)]',
          'focus-within:border-accent focus-within:bg-surface focus-within:ring-2 focus-within:ring-accent/25',
        )}
      >
        <SearchIcon className="size-4 shrink-0 text-ink-faint" />
        <input
          value={value}
          onChange={(event) => setValue(event.target.value)}
          placeholder="Search name or phone"
          aria-label="Search people"
          className="h-10 w-full bg-transparent text-sm text-ink outline-none placeholder:text-ink-faint"
        />
        {pending ? <Spinner className="size-3.5 text-ink-faint" /> : null}
        {value && !pending ? (
          <button
            type="button"
            onClick={() => setValue('')}
            aria-label="Clear search"
            className="grid size-5 shrink-0 place-items-center rounded text-ink-faint transition hover:text-ink"
          >
            <CloseIcon className="size-3.5" />
          </button>
        ) : null}
      </div>

      <button
        type="button"
        onClick={() => push(build({ archived: !includeArchived }))}
        aria-pressed={includeArchived}
        className={cn(
          'tap h-10 shrink-0 rounded-field border px-3 text-[0.8125rem] font-medium',
          'transition-[background-color,border-color,color] duration-[var(--dur)] ease-[var(--ease)]',
          includeArchived
            ? 'border-accent-line bg-accent-soft text-accent'
            : 'border-line bg-sunken text-ink-muted hover:text-ink',
        )}
      >
        Archived
      </button>
      </div>

      <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
        <div className="flex items-center gap-2">
          <span className="stat-label shrink-0" id="people-show-label">
            Show
          </span>
          <div className={SEGMENT_GROUP} role="group" aria-labelledby="people-show-label">
            {SIDES.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => push(build({ side: option.value }))}
                aria-pressed={side === option.value}
                className={segmentClass(side === option.value)}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>

        <div className="flex items-center gap-2">
          <span className="stat-label shrink-0" id="people-sort-label">
            Sort
          </span>
          <div className={SEGMENT_GROUP} role="group" aria-labelledby="people-sort-label">
            {SORTS.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => push(build({ sort: option.value }))}
                aria-pressed={sort === option.value}
                className={segmentClass(sort === option.value)}
              >
                {option.label}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
