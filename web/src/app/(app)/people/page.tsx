import Link from 'next/link';
import { getMe } from '@/lib/supabase/server';
import { getPeople } from '@/lib/queries';
import { Avatar, Badge, Card, EmptyState, PageHeader, cn } from '@/components/ui/primitives';
import { NetBadge, SplitBar } from '@/components/money';
import { initials } from '@/lib/names';
import { ArrowRightIcon, PeopleIcon } from '@/components/icons';
import { PeopleToolbar } from './people-toolbar';
import { AddPersonButton } from './add-person-button';
import { balanceTone, formatMoney } from '@/lib/money';
import { friendlyDate } from '@/lib/dates';
import type { PersonBalance } from '@/lib/types';

export const metadata = { title: 'People' };

type Sort = 'name' | 'balance' | 'recent';
type Side = 'all' | 'in' | 'out' | 'settled';

/**
 * People — the account directory (context.md §5).
 *
 * Scannable in one pass: who, how much, which way. Filters live in the URL
 * rather than component state, so a filtered list is shareable, survives a
 * refresh, and is rendered on the server (context.md §19).
 */
export default async function PeoplePage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; sort?: string; archived?: string; side?: string }>;
}) {
  const params = await searchParams;
  const query = typeof params.q === 'string' ? params.q : '';
  const sort: Sort = params.sort === 'balance' || params.sort === 'recent' ? params.sort : 'name';
  const includeArchived = params.archived === '1';
  const side: Side =
    params.side === 'in' || params.side === 'out' || params.side === 'settled'
      ? params.side
      : 'all';

  const [me, all] = await Promise.all([getMe(), getPeople({ query, sort, includeArchived })]);
  const currency = me?.currency ?? 'INR';

  // The direction filter is a view over the same rows, so it costs no extra
  // round trip and the totals below still describe the whole workspace.
  const people = all.filter((person) => {
    if (side === 'all') return true;
    const tone = balanceTone(person.net_balance);
    return side === 'settled' ? tone === 'settled' : side === 'in' ? tone === 'receivable' : tone === 'payable';
  });

  const totals = all.reduce(
    (acc, person) => ({
      receivable: acc.receivable + Math.max(person.net_balance, 0),
      payable: acc.payable + Math.max(-person.net_balance, 0),
    }),
    { receivable: 0, payable: 0 },
  );

  return (
    <div className="mx-auto w-full max-w-5xl px-4 py-6 sm:px-6 lg:px-8 lg:py-9">
      <PageHeader
        title="People"
        description={
          all.length === 0
            ? 'No one here yet'
            : `${all.length} ${all.length === 1 ? 'account' : 'accounts'} in this workspace`
        }
        action={<AddPersonButton baseCurrency={currency} />}
      />

      {all.length > 0 ? (
        /* Two figures and a bar, previously boxed in a full-width card that was
           two-thirds empty on a desktop. The card was doing no grouping work —
           these totals belong to the page, not to a container of their own — so
           the border comes off and a hairline separates them from the list.
           Not every piece of information needs a card. */
        <div className="mb-5 flex flex-wrap items-center gap-x-8 gap-y-3 border-b border-line pb-4">
          <Total label="Owed to you" amount={totals.receivable} currency={currency} tone="receivable" />
          <Total label="You owe" amount={totals.payable} currency={currency} tone="payable" />
          <div className="min-w-32 max-w-xs flex-1">
            <SplitBar receivable={totals.receivable} payable={totals.payable} />
          </div>
        </div>
      ) : null}

      <PeopleToolbar query={query} sort={sort} side={side} includeArchived={includeArchived} />

      <Card className="mt-3 overflow-hidden">
        {people.length === 0 ? (
          query ? (
            <EmptyState
              icon={<PeopleIcon />}
              title={`Nothing matches “${query}”`}
              description="Try a different name or phone number."
            />
          ) : side !== 'all' ? (
            <EmptyState
              icon={<PeopleIcon />}
              title="Nothing in this filter"
              description={
                side === 'in'
                  ? 'No one currently owes you.'
                  : side === 'out'
                    ? 'You do not currently owe anyone.'
                    : 'No accounts are fully settled.'
              }
            />
          ) : (
            <EmptyState
              icon={<PeopleIcon />}
              title="No people yet"
              description="Add your first person or business to start tracking money."
              action={<AddPersonButton baseCurrency={currency} />}
            />
          )
        ) : (
          <ul className="divide-y divide-line">
            {people.map((person) => (
              <li key={person.person_id}>
                <PersonRow person={person} currency={currency} />
              </li>
            ))}
          </ul>
        )}
      </Card>
    </div>
  );
}

/* -------------------------------------------------------------------------- */

function Total({
  label,
  amount,
  currency,
  tone,
}: {
  label: string;
  amount: number;
  currency: string;
  tone: 'receivable' | 'payable';
}) {
  return (
    <div>
      <p className="text-[0.75rem] text-ink-muted">{label}</p>
      <p
        className={cn(
          'tnum mt-0.5 font-display text-[1.125rem] font-semibold tracking-tight',
          tone === 'receivable' ? 'text-receivable' : 'text-payable',
        )}
      >
        {formatMoney(amount, currency, { base: currency })}
      </p>
    </div>
  );
}

function PersonRow({ person, currency }: { person: PersonBalance; currency: string }) {
  // Two facts, not one. The row used to show the last activity date OR the
  // transaction count — whichever was available — so an active account never
  // said how much history was behind it and a dormant one never said when it
  // went quiet. They answer different questions and both fit.
  const when =
    person.last_activity_at !== null
      ? `Last activity ${friendlyDate(person.last_activity_at)}`
      : null;
  const count =
    person.transaction_count === 0
      ? 'No transactions yet'
      : `${person.transaction_count} ${person.transaction_count === 1 ? 'transaction' : 'transactions'}`;
  const foreign = Boolean(person.currency && person.currency !== currency);

  return (
    <Link
      href={`/people/${person.person_id}`}
      className="group flex items-center gap-3 px-4 py-3 transition-colors duration-[var(--dur)] ease-[var(--ease)] hover:bg-sunken sm:px-5"
    >
      <Avatar identity={person.name}>{initials(person.name)}</Avatar>

      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-2">
          <span className="truncate text-[0.875rem] font-medium text-ink">{person.name}</span>
          {person.is_archived ? <Badge tone="muted">Archived</Badge> : null}
        </span>

        {/* When it last moved — the line a directory is actually scanned by. */}
        {when ? (
          <span className="block truncate text-[0.75rem] text-ink-muted">{when}</span>
        ) : null}

        {/* How much history, in what currency, and how to reach them. One step
            quieter again: this is the line you read after you have decided the
            row is the one you wanted. */}
        <span className="flex min-w-0 items-center gap-1.5 text-[0.75rem] text-ink-faint">
          <span className="truncate">{count}</span>
          {/* The account's own currency, when it is not the workspace's. A
              multi-currency ledger where a row does not say what it is
              denominated in is a ledger you have to click to read (§8). Written
              as the pair it actually is — the row's currency and the one the
              balance beneath it converts to. */}
          {foreign ? (
            <>
              <span className="text-ink-subtle">·</span>
              <span className="shrink-0 font-medium text-ink-muted">
                {person.currency} / {currency}
              </span>
            </>
          ) : null}
          {person.phone ? (
            <>
              <span className="text-ink-subtle">·</span>
              <span className="truncate">{person.phone}</span>
            </>
          ) : null}
        </span>
      </span>

      {/* The balance in the account's own currency, with the same position in
          the workspace's underneath when the two differ (upgrade §42). */}
      <NetBadge
        netMinor={person.net_balance}
        currency={person.currency ?? currency}
        base={currency}
        approxMinor={person.net_balance_base}
        approxCurrency={currency}
      />
      <ArrowRightIcon className="size-4 shrink-0 text-ink-faint/60 transition-transform duration-[var(--dur)] ease-[var(--ease)] group-hover:translate-x-0.5 group-hover:text-ink-muted" />
    </Link>
  );
}
