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
            className="press grid size-5 shrink-0 place-items-center rounded text-ink-faint transition-[color,transform] duration-[var(--dur-fast)] ease-[var(--ease)] hover:text-ink"
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

      {/* At 375px the four Show segments plus their label are wider than the
          viewport. A segmented control cannot wrap — broken across two lines it
          stops reading as one control — so the group scrolls inside its own
          track instead, and the page never scrolls sideways. The bleed to the
          screen edge is deliberate: a control that is cut off at the container
          padding looks broken, one that runs off the edge looks scrollable. */}
      <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
        <FilterGroup
          id="people-show-label"
          label="Show"
          options={SIDES}
          active={side}
          onSelect={(value) => push(build({ side: value }))}
        />
        <FilterGroup
          id="people-sort-label"
          label="Sort"
          options={SORTS}
          active={sort}
          onSelect={(value) => push(build({ sort: value }))}
        />
      </div>
    </div>
  );
}

/** A named segmented control that scrolls rather than wraps or overflows. */
function FilterGroup({
  id,
  label,
  options,
  active,
  onSelect,
}: {
  id: string;
  label: string;
  options: ReadonlyArray<{ value: string; label: string }>;
  active: string;
  onSelect: (value: string) => void;
}) {
  return (
    <div className="flex min-w-0 max-w-full items-center gap-2">
      <span className="stat-label shrink-0" id={id}>
        {label}
      </span>
      {/* The vertical padding keeps the focus ring off the scroll edge, which
          would otherwise clip it to a hairline on the first and last segment. */}
      <div className="-my-1 min-w-0 overflow-x-auto py-1 no-scrollbar">
        <div className={cn(SEGMENT_GROUP, 'w-max')} role="group" aria-labelledby={id}>
          {options.map((option) => (
            <button
              key={option.value}
              type="button"
              onClick={() => onSelect(option.value)}
              aria-pressed={active === option.value}
              className={segmentClass(active === option.value)}
            >
              {option.label}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
