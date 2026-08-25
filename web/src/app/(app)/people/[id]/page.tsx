import { notFound } from 'next/navigation';
import Link from 'next/link';
import type { Metadata } from 'next';
import { getMe } from '@/lib/supabase/server';
import { getPersonPage } from '@/lib/queries';
import { Avatar, Badge, Card, Panel, cn, segmentClass, SEGMENT_GROUP } from '@/components/ui/primitives';
import { Money } from '@/components/money';
import { CountUp } from '@/components/motion/count-up';
import { Sparkline } from '@/components/charts/sparkline';
import { Reveal } from '@/components/motion/reveal';
import { initials } from '@/lib/names';
import { PersonActionBar } from './person-action-bar';
import { Timeline } from './timeline';
import { balanceTone, formatMinor } from '@/lib/money';
import { currencyLabel } from '@/lib/currencies';
import { personBalanceSeries } from '@/lib/series';
import { fullDate } from '@/lib/dates';
import { ArrowRightIcon } from '@/components/icons';

const PAGE_SIZE = 30;
type Tab = 'history' | 'details' | 'notes';

export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const data = await getPersonPage(id, 1, 0);
  return { title: data?.person.name ?? 'Person' };
}

/**
 * Person / business account — the screen the product is really about
 * (context.md §6, §16).
 *
 * It reads like a statement: who, where we stand, what to do about it, then the
 * history that got us here. The net position is the largest thing on the page,
 * so "where do we stand?" needs no arithmetic from the reader, and settling is
 * the one filled button.
 *
 * The tabs are links, not state — the whole screen is server-rendered, so
 * switching to Details ships no JavaScript and survives a refresh.
 */
export default async function PersonPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ page?: string; tab?: string }>;
}) {
  const [{ id }, query] = await Promise.all([params, searchParams]);
  const pageIndex = Math.max(0, Number.parseInt(query.page ?? '0', 10) || 0);
  const tab: Tab = query.tab === 'details' || query.tab === 'notes' ? query.tab : 'history';

  const [me, data] = await Promise.all([
    getMe(),
    getPersonPage(id, PAGE_SIZE, pageIndex * PAGE_SIZE),
  ]);
  if (!data) notFound();

  // The account's own currency, not the workspace's: every figure on this page
  // is denominated in what this person is billed in (upgrade §10). That is the
  // person's LEDGER currency — what their history was actually recorded in.
  const currency = data.currency ?? me?.currency ?? 'INR';
  // And what a new entry for them defaults to. The two differ only for a person
  // whose currency was changed after they already had entries: the history
  // stayed where it was written, and new entries start in the new currency.
  const defaultCurrency = data.default_currency ?? currency;
  const currencySwitched = defaultCurrency !== currency;
  const baseCurrency = data.base_currency ?? me?.currency ?? 'INR';
  const { person, balance, timeline, timeline_total: total, open_transactions: openTxns } = data;
  const tone = balanceTone(balance.net_balance);
  const hasMore = (pageIndex + 1) * PAGE_SIZE < total;
  const series = personBalanceSeries(timeline, balance);
  const firstName = person.name.split(' ')[0];

  const tabHref = (next: Tab) => `/people/${person.id}${next === 'history' ? '' : `?tab=${next}`}`;

  return (
    <div className="mx-auto w-full max-w-4xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      <Link
        href="/people"
        className="mb-4 inline-flex items-center gap-1.5 text-[0.75rem] font-medium text-ink-faint transition-colors duration-[var(--dur)] hover:text-ink"
      >
        <ArrowRightIcon className="size-3.5 rotate-180" />
        People
      </Link>

      {/* ------------------------------------------------------------------ */}
      {/* Identity                                                            */}
      {/* ------------------------------------------------------------------ */}
      <Reveal as="header" className="mb-4 flex items-start gap-4">
        <Avatar size="lg" identity={person.name}>
          {initials(person.name)}
        </Avatar>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="page-title truncate">
              {person.name}
            </h1>
            {person.is_archived ? <Badge tone="muted">Archived</Badge> : null}
            {/* Stated always, not only when it differs from the base: "how much
                is this in?" is the first question on a multi-currency ledger,
                and a badge that appears and disappears is a worse answer than
                one that is simply always there. */}
            <Badge tone="muted">{currency}</Badge>
            {/* Only when they differ. A person who has never switched has one
                currency and should be told about exactly one. */}
            {currencySwitched ? (
              <Badge tone="muted">New entries in {defaultCurrency}</Badge>
            ) : null}
          </div>
          <p className="mt-1 truncate text-[0.8125rem] text-ink-muted">
            <span className="capitalize">{person.type}</span>
            {person.phone ? ` · ${person.phone}` : ''}
            {person.email ? ` · ${person.email}` : ''}
          </p>
        </div>
      </Reveal>

      {/* ------------------------------------------------------------------ */}
      {/* Position — both sides on one page (context.md §6)                   */}
      {/* ------------------------------------------------------------------ */}
      <Reveal delay={40}>
        <Panel>
          <div className="relative flex flex-wrap items-end justify-between gap-5 px-5 py-6 sm:px-6">
            <div className="relative min-w-0">
              <p className="text-[0.8125rem] font-medium text-ink-muted">Current position</p>
              <p
                className={cn(
                  // The account's headline figure, on the money scale like every other
                  // figure in the product — it was hand-sized at 2.25/2.75rem, which is
                  // the one place a balance was not using the money typography.
                  'money-hero mt-1.5',
                  tone === 'receivable' && 'text-receivable',
                  tone === 'payable' && 'text-payable',
                  tone === 'settled' && 'text-ink',
                )}
              >
                {/* Animates when it changes — which is exactly when a settlement
                    has just been recorded on this page. */}
                <CountUp minor={Math.abs(balance.net_balance)} currency={currency} />
              </p>
              <p
                className={cn(
                  'mt-2 text-[0.8125rem] font-medium',
                  tone === 'receivable' && 'text-receivable',
                  tone === 'payable' && 'text-payable',
                  tone === 'settled' && 'text-ink-faint',
                )}
              >
                {tone === 'receivable'
                  ? `${firstName} owes you`
                  : tone === 'payable'
                    ? `You owe ${firstName}`
                    : 'Everything is settled'}
              </p>

              {/* The same position in the workspace's currency. Shown only when
                  there is another currency to show, and labelled as an
                  approximation at today's rate, because that is what it is —
                  nothing settles against this figure. */}
              {currency !== baseCurrency && balance.net_balance !== 0 ? (
                <p className="mt-1.5 text-[0.8125rem] text-ink-faint">
                  {balance.net_balance_base === null
                    ? `No ${currency} → ${baseCurrency} rate yet`
                    : `≈ ${formatMinor(Math.abs(balance.net_balance_base), baseCurrency)} at today’s rate`}
                </p>
              ) : null}

              {balance.opening_minor !== 0 ? (
                <p className="mt-1 text-[0.75rem] text-ink-faint">
                  Includes an opening balance of{' '}
                  {formatMinor(Math.abs(balance.opening_minor), currency)}{' '}
                  {balance.opening_minor > 0 ? 'in your favour' : 'against you'}
                </p>
              ) : null}
            </div>

            {series ? (
              <div className="w-full min-w-0 max-w-xs sm:w-56">
                <Sparkline
                  id="person"
                  points={series}
                  tone={tone === 'payable' ? 'payable' : tone === 'settled' ? 'accent' : 'receivable'}
                  className="h-12"
                />
                <p className="mt-1 text-right text-[0.6875rem] text-ink-faint">
                  Balance across the last {Math.min(timeline.length, PAGE_SIZE)} entries
                </p>
              </div>
            ) : null}
          </div>

          <div className="border-t border-line px-5 py-4 sm:px-6">
            <PersonActionBar
              person={person}
              balance={balance}
              openTransactions={openTxns}
              currency={currency}
              baseCurrency={baseCurrency}
            />
          </div>

          {/* Credit / debit / settled summary */}
          <div className="grid grid-cols-2 divide-line border-t border-line bg-surface/50 sm:grid-cols-4 sm:divide-x">
            {/* Credit is what they gave you, so it is what you owe. The
                engine's total_credit counts the other direction — the mapping
                lives in lib/direction.ts and nowhere else. */}
            <Figure
              label="Credited to you"
              minor={balance.total_debit}
              currency={currency}
              tone={balance.total_debit > 0 ? 'payable' : 'neutral'}
            />
            <Figure
              label="Debited to them"
              minor={balance.total_credit}
              currency={currency}
              tone={balance.total_credit > 0 ? 'receivable' : 'neutral'}
            />
            <Figure
              label="Settled"
              minor={balance.total_settled}
              currency={currency}
              tone="neutral"
            />
            <Figure
              label={tone === 'payable' ? 'You will pay' : 'You will receive'}
              minor={
                tone === 'payable' ? balance.outstanding_payable : balance.outstanding_receivable
              }
              currency={currency}
              tone={tone === 'payable' ? 'payable' : tone === 'settled' ? 'neutral' : 'receivable'}
            />
          </div>
        </Panel>
      </Reveal>

      {/* ------------------------------------------------------------------ */}
      {/* History / details / notes                                           */}
      {/* ------------------------------------------------------------------ */}
      <section className="mt-6">
        <div className={cn(SEGMENT_GROUP, 'mb-3')} role="tablist" aria-label="Account sections">
          {(['history', 'details', 'notes'] as const).map((value) => (
            <Link
              key={value}
              href={tabHref(value)}
              scroll={false}
              role="tab"
              aria-selected={tab === value}
              className={cn(segmentClass(tab === value), 'capitalize')}
            >
              {value === 'history' ? 'History' : value === 'details' ? 'Details' : 'Notes'}
            </Link>
          ))}
        </div>

        {tab === 'history' ? (
          <>
            <Timeline
              entries={timeline}
              person={person}
              balance={balance}
              openTransactions={openTxns}
              currency={currency}
            />

            {(hasMore || pageIndex > 0) && (
              <div className="mt-4 flex items-center justify-between">
                {pageIndex > 0 ? (
                  <PageLink
                    href={`/people/${person.id}${pageIndex > 1 ? `?page=${pageIndex - 1}` : ''}`}
                  >
                    ← Newer
                  </PageLink>
                ) : (
                  <span />
                )}
                {hasMore ? (
                  <PageLink href={`/people/${person.id}?page=${pageIndex + 1}`}>Older →</PageLink>
                ) : (
                  <span />
                )}
              </div>
            )}
          </>
        ) : tab === 'details' ? (
          <Card className="divide-y divide-line">
            <Detail label="Type" value={person.type} className="capitalize" />
            <Detail label="Currency" value={currencyLabel(currency)} />
            <Detail label="Phone" value={person.phone ?? '—'} />
            <Detail label="Email" value={person.email ?? '—'} />
            <Detail label="Transactions" value={String(balance.transaction_count)} />
            <Detail
              label="Last activity"
              value={balance.last_activity_at ? fullDate(balance.last_activity_at) : 'None yet'}
            />
            <Detail
              label="Lifetime volume"
              value={formatMinor(balance.total_credit + balance.total_debit, currency)}
            />
            <Detail label="Status" value={person.is_archived ? 'Archived' : 'Active'} />
          </Card>
        ) : (
          <Card className="px-5 py-4">
            {person.notes ? (
              <p className="whitespace-pre-wrap text-[0.875rem] leading-relaxed text-ink-muted">
                {person.notes}
              </p>
            ) : (
              <p className="py-6 text-center text-[0.8125rem] text-ink-faint">
                No notes on this account. Add them from the edit dialog.
              </p>
            )}
          </Card>
        )}
      </section>
    </div>
  );
}

/* -------------------------------------------------------------------------- */

function Figure({
  label,
  minor,
  currency,
  tone,
}: {
  label: string;
  minor: number;
  currency: string;
  tone: 'receivable' | 'payable' | 'neutral';
}) {
  return (
    <div className="border-b border-line px-4 py-3.5 last:border-b-0 sm:border-b-0 sm:px-5">
      <p className="truncate text-[0.75rem] text-ink-muted">{label}</p>
      <p className="mt-1 truncate text-[1rem] font-semibold">
        <Money minor={minor} currency={currency} tone={tone} />
      </p>
    </div>
  );
}

function Detail({
  label,
  value,
  className,
}: {
  label: string;
  value: string;
  className?: string;
}) {
  return (
    <div className="flex items-center justify-between gap-4 px-5 py-3">
      <span className="text-[0.8125rem] text-ink-muted">{label}</span>
      <span className={cn('truncate text-[0.8125rem] font-medium text-ink', className)}>
        {value}
      </span>
    </div>
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
