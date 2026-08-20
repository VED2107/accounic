'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { Modal } from '@/components/ui/modal';
import { Avatar, Skeleton, cn } from '@/components/ui/primitives';
import { NetBadge } from '@/components/money';
import { formatMinor } from '@/lib/money';
import { friendlyDate } from '@/lib/dates';
import { SearchIcon } from '@/components/icons';
import { initials } from '@/lib/names';
import { isReceivable } from '@/lib/direction';
import type { SearchResults } from '@/lib/types';

/**
 * Global search (context.md §15).
 *
 * People rank above transactions because that is what a user is nearly always
 * looking for. Input is debounced and every response carries a sequence number,
 * so a slow early request can never overwrite a fast later one.
 */
export function QuickSearch({
  open,
  onClose,
  currency,
}: {
  open: boolean;
  onClose: () => void;
  currency: string;
}) {
  const router = useRouter();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResults | null>(null);
  const [loading, setLoading] = useState(false);
  const [highlight, setHighlight] = useState(0);
  const sequence = useRef(0);

  useEffect(() => {
    if (!open) {
      setQuery('');
      setResults(null);
      setHighlight(0);
    }
  }, [open]);

  useEffect(() => {
    const trimmed = query.trim();
    if (trimmed.length === 0) {
      setResults(null);
      setLoading(false);
      return;
    }

    setLoading(true);
    const ticket = ++sequence.current;
    const timer = window.setTimeout(async () => {
      const { data, error } = await createClient().rpc('search_all', {
        p_query: trimmed,
        p_limit: 8,
      });
      if (ticket !== sequence.current) return; // a newer keystroke already won
      setLoading(false);
      setResults(error ? { people: [], transactions: [] } : (data as SearchResults));
      setHighlight(0);
    }, 160);

    return () => window.clearTimeout(timer);
  }, [query]);

  const people = results?.people ?? [];
  const transactions = results?.transactions ?? [];
  const flat = [
    ...people.map((p) => `/people/${p.person_id}`),
    ...transactions.map((t) => `/people/${t.person_id}`),
  ];

  function go(href: string) {
    onClose();
    router.push(href);
  }

  return (
    <Modal open={open} onClose={onClose} title="Search" size="lg">
      <div className="space-y-4">
        <div className="flex items-center gap-3 rounded-field border border-line bg-sunken px-3 focus-within:border-accent focus-within:bg-surface focus-within:ring-2 focus-within:ring-accent/25">
          <SearchIcon className="size-4 shrink-0 text-ink-faint" />
          <input
            data-autofocus="true"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === 'ArrowDown') {
                event.preventDefault();
                setHighlight((h) => Math.min(h + 1, flat.length - 1));
              } else if (event.key === 'ArrowUp') {
                event.preventDefault();
                setHighlight((h) => Math.max(h - 1, 0));
              } else if (event.key === 'Enter') {
                const href = flat[highlight];
                if (href) {
                  event.preventDefault();
                  go(href);
                }
              }
            }}
            placeholder="Search people, phone numbers or notes…"
            aria-label="Search"
            className="h-11 flex-1 bg-transparent text-[0.9375rem] text-ink outline-none placeholder:text-ink-faint"
          />
        </div>

        <div className="max-h-[55dvh] min-h-24 overflow-y-auto">
          {loading && !results ? (
            <div className="space-y-2 py-1">
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-full" />
              <Skeleton className="h-12 w-2/3" />
            </div>
          ) : query.trim().length === 0 ? (
            <p className="px-1 py-6 text-center text-sm text-ink-faint">
              Start typing to find a person or a transaction note.
            </p>
          ) : people.length === 0 && transactions.length === 0 ? (
            <p className="px-1 py-6 text-center text-sm text-ink-faint">
              Nothing matches “{query.trim()}”.
            </p>
          ) : (
            <div className="space-y-4">
              {people.length > 0 ? (
                <section>
                  <p className="px-1 pb-1.5 text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
                    People
                  </p>
                  <ul>
                    {people.map((person, index) => (
                      <li key={person.person_id}>
                        <button
                          type="button"
                          onMouseEnter={() => setHighlight(index)}
                          onClick={() => go(`/people/${person.person_id}`)}
                          className={cn(
                            'flex w-full items-center gap-3 rounded-field px-3 py-2.5 text-left',
                            'transition-colors duration-[var(--dur)] ease-[var(--ease)]',
                            highlight === index ? 'bg-sunken' : 'hover:bg-sunken',
                          )}
                        >
                          <Avatar identity={person.name} size="sm">
                            {initials(person.name)}
                          </Avatar>
                          <span className="min-w-0 flex-1">
                            <span className="block truncate text-sm font-medium text-ink">
                              {person.name}
                              {person.is_archived ? (
                                <span className="ml-2 text-xs font-normal text-ink-faint">
                                  Archived
                                </span>
                              ) : null}
                            </span>
                            {person.phone ? (
                              <span className="block truncate text-xs text-ink-faint">
                                {person.phone}
                              </span>
                            ) : null}
                          </span>
                          <NetBadge netMinor={person.net_balance} currency={currency} />
                        </button>
                      </li>
                    ))}
                  </ul>
                </section>
              ) : null}

              {transactions.length > 0 ? (
                <section>
                  <p className="px-1 pb-1.5 text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
                    Transactions
                  </p>
                  <ul>
                    {transactions.map((txn, index) => {
                      const flatIndex = people.length + index;
                      return (
                        <li key={txn.id}>
                          <button
                            type="button"
                            onMouseEnter={() => setHighlight(flatIndex)}
                            onClick={() => go(`/people/${txn.person_id}`)}
                            className={cn(
                              'flex w-full items-center gap-3 rounded-field px-3 py-2.5 text-left',
                              'transition-colors duration-[var(--dur)] ease-[var(--ease)]',
                              highlight === flatIndex ? 'bg-sunken' : 'hover:bg-sunken',
                            )}
                          >
                            <span className="min-w-0 flex-1">
                              <span className="block truncate text-sm text-ink">
                                {txn.description}
                              </span>
                              <span className="block truncate text-xs text-ink-faint">
                                {txn.person_name} · {friendlyDate(txn.transaction_date)}
                              </span>
                            </span>
                            <span
                              className={`tnum shrink-0 text-sm font-medium ${
                                isReceivable(txn.type) ? 'text-receivable' : 'text-payable'
                              }`}
                            >
                              {formatMinor(txn.amount_minor, currency)}
                            </span>
                          </button>
                        </li>
                      );
                    })}
                  </ul>
                </section>
              ) : null}
            </div>
          )}
        </div>
      </div>
    </Modal>
  );
}
