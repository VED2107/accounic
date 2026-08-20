'use client';

import { useEffect, useRef, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { initials } from '@/lib/names';
import { NetBadge } from '@/components/money';
import { PlusIcon, SearchIcon } from '@/components/icons';
import { Avatar, Spinner, cn } from '@/components/ui/primitives';

export interface PickedPerson {
  id: string;
  name: string;
}

/**
 * "Who?" — the first field of fast transaction entry (context.md §14).
 *
 * Searching and creating live in the same control: typing a name that does not
 * exist offers to create it inline, so adding a transaction for a brand new
 * customer never means leaving the form.
 */
export function PersonPicker({
  value,
  onChange,
  currency,
}: {
  value: PickedPerson | null;
  onChange: (person: PickedPerson | null) => void;
  currency: string;
}) {
  const [query, setQuery] = useState('');
  const [options, setOptions] = useState<
    Array<{ person_id: string; name: string; phone: string | null; net_balance: number }>
  >([]);
  const [loading, setLoading] = useState(false);
  const [creating, setCreating] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const sequence = useRef(0);

  useEffect(() => {
    if (value) return;
    const trimmed = query.trim();
    setLoading(true);
    const ticket = ++sequence.current;

    const timer = window.setTimeout(async () => {
      const supabase = createClient();
      const request = trimmed
        ? supabase.rpc('search_all', { p_query: trimmed, p_limit: 6 })
        : supabase
            .from('person_balances')
            .select('person_id, name, phone, net_balance')
            .eq('is_archived', false)
            .order('last_activity_at', { ascending: false, nullsFirst: false })
            .limit(6);

      const { data, error: queryError } = await request;
      if (ticket !== sequence.current) return;

      setLoading(false);
      if (queryError) {
        setOptions([]);
        return;
      }
      setOptions(
        trimmed
          ? ((data as { people: typeof options }).people ?? [])
          : ((data as typeof options) ?? []),
      );
    }, 140);

    return () => window.clearTimeout(timer);
  }, [query, value]);

  async function createInline() {
    const name = query.trim();
    if (!name) return;
    setCreating(true);
    setError(null);

    const { data, error: rpcError } = await createClient().rpc('create_person', { p_name: name });
    setCreating(false);

    if (rpcError || !data) {
      setError('That person could not be created. Please try again.');
      return;
    }
    const created = data as { id: string; name: string };
    onChange({ id: created.id, name: created.name });
  }

  if (value) {
    return (
      <div className="space-y-1.5">
        <span className="block text-[0.8125rem] font-medium text-ink-muted">Who?</span>
        <div className="flex items-center gap-3 rounded-field border border-line-strong bg-sunken px-3 py-2.5">
          <Avatar tone="accent" size="sm">
            {initials(value.name)}
          </Avatar>
          <span className="min-w-0 flex-1 truncate text-[0.875rem] font-medium text-ink">
            {value.name}
          </span>
          <button
            type="button"
            onClick={() => {
              onChange(null);
              setQuery('');
            }}
            className="shrink-0 text-[0.8125rem] font-medium text-accent transition hover:underline"
          >
            Change
          </button>
        </div>
      </div>
    );
  }

  const exactMatch = options.some((o) => o.name.toLowerCase() === query.trim().toLowerCase());

  return (
    <div className="space-y-1.5">
      <label htmlFor="person-search" className="block text-[0.8125rem] font-medium text-ink-muted">
        Who?
      </label>
      <div className="flex items-center gap-2 rounded-field border border-line-strong bg-sunken px-3 transition-[border-color,background-color] duration-[var(--dur)] focus-within:border-accent focus-within:bg-surface focus-within:ring-2 focus-within:ring-accent/25">
        <SearchIcon className="size-4 shrink-0 text-ink-faint" />
        <input
          id="person-search"
          data-autofocus="true"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder="Search or type a new name"
          autoComplete="off"
          className="h-10 w-full bg-transparent text-sm text-ink outline-none placeholder:text-ink-faint"
        />
        {loading ? <Spinner className="size-3.5 text-ink-faint" /> : null}
      </div>

      {error ? (
        <p className="text-[0.8125rem] text-payable" role="alert">
          {error}
        </p>
      ) : null}

      <ul className="max-h-56 overflow-y-auto rounded-field border border-line bg-surface">
        {options.map((option) => (
          <li key={option.person_id}>
            <button
              type="button"
              onClick={() => onChange({ id: option.person_id, name: option.name })}
              className={cn(
                'flex w-full items-center gap-3 border-b border-line px-3 py-2.5 text-left last:border-0',
                'transition-colors duration-[var(--dur)] ease-[var(--ease)] hover:bg-sunken',
              )}
            >
              <Avatar size="sm">{initials(option.name)}</Avatar>
              <span className="min-w-0 flex-1">
                <span className="block truncate text-[0.875rem] font-medium text-ink">
                  {option.name}
                </span>
                {option.phone ? (
                  <span className="block truncate text-[0.75rem] text-ink-faint">
                    {option.phone}
                  </span>
                ) : null}
              </span>
              <NetBadge netMinor={option.net_balance} currency={currency} />
            </button>
          </li>
        ))}

        {query.trim() && !exactMatch ? (
          <li>
            <button
              type="button"
              onClick={createInline}
              disabled={creating}
              className="flex w-full items-center gap-3 px-3 py-2.5 text-left transition-colors duration-[var(--dur)] hover:bg-sunken disabled:opacity-60"
            >
              <span className="grid size-8 shrink-0 place-items-center rounded-[0.625rem] border border-accent-line bg-accent-soft text-accent">
                {creating ? <Spinner className="size-3.5" /> : <PlusIcon className="size-4" />}
              </span>
              <span className="min-w-0 flex-1 truncate text-[0.875rem] text-ink">
                Add <span className="font-medium">{query.trim()}</span> as a new person
              </span>
            </button>
          </li>
        ) : null}

        {options.length === 0 && !query.trim() && !loading ? (
          <li className="px-3 py-6 text-center text-[0.8125rem] text-ink-faint">
            Type a name to search or create.
          </li>
        ) : null}
      </ul>
    </div>
  );
}
