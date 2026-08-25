import Link from 'next/link';
import { getMe } from '@/lib/supabase/server';
import { getActivity, getActivitySummary } from '@/lib/queries';
import {
  Card,
  EmptyState,
  PageHeader,
  SEGMENT_GROUP,
  cn,
  segmentClass,
} from '@/components/ui/primitives';
import { Money } from '@/components/money';
import { Sparkline } from '@/components/charts/sparkline';
import { ActivityRow } from '@/components/ledger/activity-row';
import { AddTransactionButton } from '@/components/ledger/add-transaction-button';
import { Reveal, staggerStyle } from '@/components/motion/reveal';
import { ActivityIcon } from '@/components/icons';
import { dayGroupLabel, groupByDate } from '@/lib/dates';
import { trendsFromBuckets } from '@/lib/series';

export const metadata = { title: 'Activity' };

const PAGE_SIZE = 40;
type Kind = 'transaction' | 'settlement';

/**
 * Workspace activity (context.md §16, §30).
 *
 * A financial timeline, not a table: everything that happened, newest first,
 * grouped by the day it happened on and headed the way a person would say the
 * date out loud. The 30-day totals at the top are the whole of v1 reporting —
 * the spec is explicit that a reporting engine is not wanted yet.
 */
export default async function ActivityPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; kind?: string }>;
}) {
  const params = await searchParams;
  const pageIndex = Math.max(0, Number.parseInt(params.page ?? '0', 10) || 0);
  const kind: Kind | undefined =
    params.kind === 'transaction' || params.kind === 'settlement' ? params.kind : undefined;

  const [me, activity, buckets] = await Promise.all([
    getMe(),
    getActivity(pageIndex, PAGE_SIZE, kind),
    getActivitySummary('day', 30),
  ]);

  const currency = me?.currency ?? 'INR';
  const totals = buckets.reduce(
    (acc, bucket) => ({
      credit: acc.credit + bucket.credit,
      debit: acc.debit + bucket.debit,
      settled: acc.settled + bucket.settled,
    }),
    { credit: 0, debit: 0, settled: 0 },
  );
  const trends = trendsFromBuckets(buckets);
  const groups = groupByDate(activity.items, dayGroupLabel);

  function href(next: { page?: number; kind?: Kind | undefined }) {
    const query = new URLSearchParams();
    const nextKind = 'kind' in next ? next.kind : kind;
    const nextPage = next.page ?? 0;
    if (nextKind) query.set('kind', nextKind);
    if (nextPage > 0) query.set('page', String(nextPage));
    return query.size ? `/activity?${query}` : '/activity';
  }

  return (
    <div className="mx-auto w-full max-w-4xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <Reveal>
        <PageHeader
          title="Activity"
          description={`${activity.total} ${activity.total === 1 ? 'entry' : 'entries'} in this workspace`}
        />
      </Reveal>

      <Reveal delay={40}>
        <div className="grid gap-3 sm:grid-cols-3">
          {/* Credit is money the person gave the owner, so it is what the
              owner owes — the payable side. The engine's `credit` bucket counts
              the other direction; see lib/direction.ts. */}
          <SummaryCard
            id="a-credit"
            label="Credit"
            caption="They gave you"
            amount={totals.debit}
            currency={currency}
            tone="payable"
            points={trends.debit.points}
          />
          <SummaryCard
            id="a-debit"
            label="Debit"
            caption="You gave them"
            amount={totals.credit}
            currency={currency}
            tone="receivable"
            points={trends.credit.points}
          />
          <SummaryCard
            id="a-settled"
            label="Settled"
            caption="Closed either way"
            amount={totals.settled}
            currency={currency}
            tone="neutral"
          />
        </div>
      </Reveal>

      <div className={cn(SEGMENT_GROUP, 'mt-4')} role="group" aria-label="Filter activity">
        {(
          [
            { value: undefined, label: 'Everything' },
            { value: 'transaction' as const, label: 'Transactions' },
            { value: 'settlement' as const, label: 'Settlements' },
          ] satisfies Array<{ value: Kind | undefined; label: string }>
        ).map((tab) => (
          <Link
            key={tab.label}
            href={href({ kind: tab.value, page: 0 })}
            scroll={false}
            aria-current={kind === tab.value ? 'true' : undefined}
            className={segmentClass(kind === tab.value)}
          >
            {tab.label}
          </Link>
        ))}
      </div>

      {activity.items.length === 0 ? (
        <Card className="mt-3">
          <EmptyState
            icon={<ActivityIcon />}
            title="Nothing here yet"
            description="Transactions and settlements will appear here as you record them."
            action={<AddTransactionButton currency={currency} />}
          />
        </Card>
      ) : (
        <div className="mt-4 space-y-5">
          {groups.map((group, groupIndex) => (
            <Reveal key={group.date} delay={Math.min(groupIndex, 4) * 30}>
              <p className="mb-2 flex items-center gap-3 px-1 text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
                {group.label}
                <span aria-hidden className="h-px flex-1 bg-line" />
                <span className="tnum font-normal normal-case tracking-normal">
                  {group.items.length} {group.items.length === 1 ? 'entry' : 'entries'}
                </span>
              </p>
              <Card className="overflow-hidden">
                <ul className="divide-y divide-line">
                  {group.items.map((item, index) => (
                    <li
                      key={`${item.entry_kind}-${item.id}`}
                      className="reveal-row"
                      style={staggerStyle(index)}
                    >
                      <ActivityRow item={item} currency={currency} />
                    </li>
                  ))}
                </ul>
              </Card>
            </Reveal>
          ))}
        </div>
      )}

      {(activity.has_more || pageIndex > 0) && (
        <div className="mt-5 flex items-center justify-between">
          {pageIndex > 0 ? (
            <PageLink href={href({ page: pageIndex - 1 })}>← Newer</PageLink>
          ) : (
            <span />
          )}
          {activity.has_more ? (
            <PageLink href={href({ page: pageIndex + 1 })}>Older →</PageLink>
          ) : (
            <span />
          )}
        </div>
      )}
    </div>
  );
}

/* -------------------------------------------------------------------------- */

function SummaryCard({
  id,
  label,
  caption,
  amount,
  currency,
  tone,
  points,
}: {
  id: string;
  label: string;
  caption: string;
  amount: number;
  currency: string;
  tone: 'receivable' | 'payable' | 'neutral';
  points?: number[];
}) {
  return (
    <Card className="lift px-4 py-3.5">
      <div className="flex items-center justify-between gap-2">
        <p className="text-[0.75rem] font-medium text-ink">{label}</p>
        <span className="text-[0.625rem] uppercase tracking-wider text-ink-faint">30 days</span>
      </div>
      <div className="mt-1 flex items-end justify-between gap-3">
        <p className="truncate font-display text-[1.25rem] font-semibold tracking-tight">
          <Money minor={amount} currency={currency} tone={tone} />
        </p>
        {points && points.length > 1 ? (
          <div className="w-14 shrink-0">
            <Sparkline
              id={id}
              points={points}
              tone={tone === 'neutral' ? 'accent' : tone}
              className="h-6"
              area={false}
            />
          </div>
        ) : null}
      </div>
      <p className="mt-1 text-[0.6875rem] text-ink-faint">{caption}</p>
    </Card>
  );
}

function PageLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="rounded-field border border-line bg-surface px-3 py-1.5 text-[0.8125rem] font-medium text-ink-muted transition-[color,border-color] duration-[var(--dur)] hover:border-line-strong hover:text-ink"
    >
      {children}
    </Link>
  );
}
