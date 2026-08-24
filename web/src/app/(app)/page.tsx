import Link from 'next/link';
import { getActivitySummary, getDashboard } from '@/lib/queries';
import { Avatar, Card, EmptyState, buttonClass, cn } from '@/components/ui/primitives';
import { Money, NetBadge, SplitBar } from '@/components/money';
import { Sparkline, TrendChip } from '@/components/charts/sparkline';
import { ActivityRow } from '@/components/ledger/activity-row';
import { Reveal, staggerStyle } from '@/components/motion/reveal';
import { QuickActions } from './dashboard-quick-actions';
import { initials } from '@/lib/names';
import {
  ActivityIcon,
  ArrowDownIcon,
  ArrowRightIcon,
  ArrowUpIcon,
  PeopleIcon,
  SettleIcon,
  SparkIcon,
  TrendUpIcon,
} from '@/components/icons';
import { friendlyDate, greeting } from '@/lib/dates';
import { balanceTone, formatMinor } from '@/lib/money';
import { trendsFromBuckets, type Trend } from '@/lib/series';
import type { Dashboard, DashboardPeopleRow } from '@/lib/types';

export const metadata = { title: 'Dashboard' };

/**
 * Dashboard (context.md §13).
 *
 * One question, answered in the first two seconds: how am I doing right now?
 * Three figures say it, the two lists underneath say who and what, and the pair
 * at the bottom says what it means and what to do next.
 *
 * Two RPC calls, both on the server. The sparklines are drawn from the same
 * thirty-day summary the activity page already uses — no chart library, no
 * client-side fetch, and not a single invented data point.
 */
export default async function DashboardPage() {
  const [data, buckets] = await Promise.all([getDashboard(), getActivitySummary('day', 30)]);
  const { summary, profile, today, people_with_balance: people } = data;
  // The RPC returns a generous slice; six rows is what keeps this column the
  // same height as the one beside it, and "recent" stops meaning much past that.
  const activity = data.recent_activity.slice(0, 6);
  const currency = profile.currency;
  const trends = trendsFromBuckets(buckets);

  const owing = people.filter((person) => person.net_balance > 0).length;
  const owed = people.filter((person) => person.net_balance < 0).length;
  const net = summary.net_position;
  const netTone = balanceTone(net);
  const insights = buildInsights(data, trends, currency);

  return (
    <div className="mx-auto w-full max-w-6xl px-4 py-6 sm:px-6 lg:px-8 lg:py-8">
      {/* ------------------------------------------------------------------ */}
      {/* Greeting + today's movement                                         */}
      {/* ------------------------------------------------------------------ */}
      <Reveal as="header" className="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div className="min-w-0">
          <p className="text-[0.8125rem] text-ink-muted">
            {greeting()}, {profile.name.split(' ')[0]}
          </p>
          <h1 className="mt-0.5 font-display text-[1.6rem] font-semibold tracking-tight sm:text-[1.8rem]">
            Here’s your money overview
          </h1>
        </div>

        {today.count > 0 ? (
          <div className="flex flex-wrap items-center gap-2 text-[0.75rem]">
            <span className="text-ink-faint">Today</span>
            {today.credit > 0 ? (
              <TodayChip tone="receivable" label="in">
                {formatMinor(today.credit, currency)}
              </TodayChip>
            ) : null}
            {today.debit > 0 ? (
              <TodayChip tone="payable" label="out">
                {formatMinor(today.debit, currency)}
              </TodayChip>
            ) : null}
            {today.settled > 0 ? (
              <TodayChip tone="neutral" label="settled">
                {formatMinor(today.settled, currency)}
              </TodayChip>
            ) : null}
          </div>
        ) : null}
      </Reveal>

      {/* ------------------------------------------------------------------ */}
      {/* Net position leads; the rest is its working (context.md §13).       */}
      {/*                                                                     */}
      {/* The three figures used to sit in one equal row, which made the      */}
      {/* dashboard say three things at once and none of them loudest. Net is */}
      {/* the answer to "how am I doing", so it takes the full measure and    */}
      {/* the largest number on the page; receivable, payable and settled sit */}
      {/* under it as the arithmetic behind it.                               */}
      {/* ------------------------------------------------------------------ */}
      <Reveal delay={40}>
        <Card className="brand-rule lift relative overflow-hidden bg-raised p-5 shadow-[var(--shadow-raised)] sm:p-6">
          <div className="flex flex-wrap items-start justify-between gap-x-6 gap-y-4">
            <div className="min-w-0">
              <div className="flex items-center gap-2">
                <span className="grid size-6 place-items-center rounded-md border border-accent-line bg-accent-soft text-accent">
                  <TrendUpIcon className="size-3.5" />
                </span>
                <p className="stat-label">Net position</p>
              </div>

              <p className="money-hero mt-2.5 truncate">
                <Money
                  minor={Math.abs(net)}
                  currency={currency}
                  tone={
                    netTone === 'receivable'
                      ? 'receivable'
                      : netTone === 'payable'
                        ? 'payable'
                        : 'neutral'
                  }
                />
              </p>

              {/* The state in words as well as in colour (§29). */}
              <p
                className={cn(
                  'mt-1.5 text-[0.9375rem] font-medium',
                  netTone === 'receivable' && 'text-receivable',
                  netTone === 'payable' && 'text-payable',
                  netTone === 'settled' && 'text-ink-muted',
                )}
              >
                {net > 0 ? 'You are ahead' : net < 0 ? 'You are behind' : 'Everything is settled'}
              </p>
              <p className="stat-note mt-0.5">
                Across {summary.people_with_balance}{' '}
                {summary.people_with_balance === 1 ? 'account' : 'accounts'}
                {summary.currency_count > 1 ? ` · totalled in ${currency}` : ''}
              </p>

              {/* Totals across currencies are only as complete as the rates
                  behind them. Saying how many accounts could not be converted
                  is more honest than quietly leaving them out (upgrade §9). */}
              {summary.unconverted_people > 0 ? (
                <p className="mt-2 rounded-lg border border-payable-line bg-payable-soft px-2.5 py-1.5 text-[0.8125rem] text-payable">
                  {summary.unconverted_people}{' '}
                  {summary.unconverted_people === 1 ? 'account is' : 'accounts are'} not included —
                  no exchange rate yet
                </p>
              ) : null}
            </div>

            <div className="flex min-w-0 flex-1 flex-col items-end gap-2">
              <span className="stat-label">Last 30 days</span>
              <div className="w-full max-w-[16rem]">
                <Sparkline id="net" points={trends.net.points} tone="accent" />
              </div>
            </div>
          </div>

          {summary.total_receivable > 0 && summary.total_payable > 0 ? (
            <div className="mt-5 border-t border-line pt-3">
              <SplitBar receivable={summary.total_receivable} payable={summary.total_payable} />
              <p className="mt-2 flex items-center justify-between text-[0.75rem]">
                <span className="text-receivable">
                  in {formatMinor(summary.total_receivable, currency)}
                </span>
                <span className="text-payable">
                  out {formatMinor(summary.total_payable, currency)}
                </span>
              </p>
            </div>
          ) : null}
        </Card>
      </Reveal>

      <section className="mt-3 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        <Reveal delay={80}>
          <StatCard
            id="recv"
            tone="receivable"
            icon={<ArrowDownIcon className="size-4" />}
            label="Receivable"
            caption="Money owed to you"
            amount={summary.total_receivable}
            currency={currency}
            trend={trends.credit}
            goodWhenUp
            footnote={owing > 0 ? `${owing} ${owing === 1 ? 'account' : 'accounts'}` : 'Nobody owes you'}
          />
        </Reveal>

        <Reveal delay={110}>
          <StatCard
            id="pay"
            tone="payable"
            icon={<ArrowUpIcon className="size-4" />}
            label="Payable"
            caption="Money you owe"
            amount={summary.total_payable}
            currency={currency}
            trend={trends.debit}
            goodWhenUp={false}
            footnote={owed > 0 ? `${owed} ${owed === 1 ? 'account' : 'accounts'}` : 'You owe nobody'}
          />
        </Reveal>

        <Reveal delay={140} className="sm:col-span-2 lg:col-span-1">
          <StatCard
            id="settled"
            tone="neutral"
            icon={<SettleIcon className="size-4" />}
            label="Settled"
            caption="Cleared, either way"
            amount={summary.gross_settled}
            currency={currency}
            trend={trends.settled}
            goodWhenUp
            footnote="All time"
          />
        </Reveal>
      </section>

      {/* ------------------------------------------------------------------ */}
      {/* Who, and what just happened                                         */}
      {/* ------------------------------------------------------------------ */}
      <div className="mt-4 grid items-start gap-4 lg:grid-cols-[1.05fr_1fr]">
        <Reveal delay={150}>
          <Card className="overflow-hidden">
            <SectionBar title="Outstanding balances" href="/people" linkLabel="View all" />

            {people.length === 0 ? (
              <EmptyState
                icon={<PeopleIcon />}
                title={summary.people_count === 0 ? 'No people yet' : 'Everything is settled'}
                description={
                  summary.people_count === 0
                    ? 'Add your first person or business to start tracking money.'
                    : 'No one owes you and you owe no one. Nice place to be.'
                }
                action={
                  summary.people_count === 0 ? (
                    <Link href="/people" className={buttonClass('primary', 'md')}>
                      Add person
                    </Link>
                  ) : undefined
                }
              />
            ) : (
              <ul className="divide-y divide-line">
                {people.map((person, index) => (
                  <li key={person.person_id} className="reveal-row" style={staggerStyle(index)}>
                    <BalanceRow person={person} currency={currency} />
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </Reveal>

        <Reveal delay={180}>
          <Card className="overflow-hidden">
            <SectionBar title="Recent activity" href="/activity" linkLabel="View all" />

            {activity.length === 0 ? (
              <EmptyState
                icon={<ActivityIcon />}
                title="No transactions yet"
                description="Record one and it will appear here straight away."
              />
            ) : (
              <ul className="divide-y divide-line">
                {activity.map((item, index) => (
                  <li
                    key={`${item.entry_kind}-${item.id}`}
                    className="reveal-row"
                    style={staggerStyle(index)}
                  >
                    <ActivityRow item={item} currency={currency} showDate />
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </Reveal>
      </div>

      {/* ------------------------------------------------------------------ */}
      {/* What it means, and what to do next                                  */}
      {/* ------------------------------------------------------------------ */}
      <div className="mt-4 grid items-start gap-4 lg:grid-cols-[1.05fr_1fr]">
        <Reveal delay={200}>
          <Card className="h-full overflow-hidden">
            <div className="flex items-center gap-2 border-b border-line px-5 py-3.5">
              <SparkIcon className="size-4 text-accent" />
              <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                Insights
              </h2>
            </div>
            {insights.length === 0 ? (
              <EmptyState
                title="Nothing to point out yet"
                description="Once there is a month of history here, patterns worth mentioning will show up."
              />
            ) : (
              <ul className="divide-y divide-line">
                {insights.map((insight) => (
                  <li key={insight.title} className="flex gap-3 px-5 py-3.5">
                    <span
                      className={cn(
                        'mt-0.5 size-1.5 shrink-0 rounded-full',
                        insight.tone === 'receivable' && 'bg-receivable',
                        insight.tone === 'payable' && 'bg-payable',
                        insight.tone === 'neutral' && 'bg-accent',
                      )}
                    />
                    <span className="min-w-0">
                      <span className="block text-[0.8125rem] font-medium text-ink">
                        {insight.title}
                      </span>
                      <span className="mt-0.5 block text-[0.8125rem] leading-relaxed text-ink-muted">
                        {insight.body}
                      </span>
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </Reveal>

        <Reveal delay={220}>
          <Card className="h-full overflow-hidden">
            <div className="border-b border-line px-5 py-3.5">
              <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                Quick actions
              </h2>
            </div>
            <QuickActions currency={currency} />
          </Card>
        </Reveal>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Insights — statements about the numbers already on screen, never new data.  */
/* -------------------------------------------------------------------------- */

interface Insight {
  title: string;
  body: string;
  tone: 'receivable' | 'payable' | 'neutral';
}

function buildInsights(
  data: Dashboard,
  trends: { credit: Trend; debit: Trend; net: Trend },
  currency: string,
): Insight[] {
  const { summary, people_with_balance: people } = data;
  const insights: Insight[] = [];

  // 1. Concentration: is one account carrying most of what is owed to you?
  const top = people.filter((p) => p.net_balance > 0).sort((a, b) => b.net_balance - a.net_balance)[0];
  if (top && summary.total_receivable > 0) {
    const share = Math.round((top.net_balance / summary.total_receivable) * 100);
    if (share >= 40) {
      insights.push({
        tone: 'receivable',
        title: `${top.name} holds ${share}% of your receivable`,
        body: `${formatMinor(top.net_balance, currency)} of the ${formatMinor(summary.total_receivable, currency)} owed to you sits with one account. Worth chasing first.`,
      });
    }
  }

  // 2. Momentum over the window, but only when it is a real movement. The
  //    engine's `credit` bucket is the owner-to-person direction, which the
  //    product calls a debit (lib/direction.ts).
  if (trends.credit.changePercent !== null && Math.abs(trends.credit.changePercent) >= 5) {
    const up = trends.credit.changePercent > 0;
    insights.push({
      tone: up ? 'receivable' : 'neutral',
      title: `Money you lent out is ${up ? 'up' : 'down'} ${Math.abs(Math.round(trends.credit.changePercent))}%`,
      body: `${formatMinor(trends.credit.total, currency)} of debits in the last 30 days, ${up ? 'more' : 'less'} in the recent half of that window than the earlier half.`,
    });
  }

  // 3. Anything sitting untouched. Stale receivables are the thing that bites.
  const stale = people
    .filter((p) => p.net_balance > 0 && p.last_activity_at !== null)
    .sort((a, b) => (a.last_activity_at! < b.last_activity_at! ? -1 : 1))[0];
  if (stale) {
    const days = Math.round(
      (Date.now() - new Date(stale.last_activity_at!).getTime()) / 86_400_000,
    );
    if (days >= 14) {
      insights.push({
        tone: 'payable',
        title: `Nothing from ${stale.name} in ${days} days`,
        body: `${formatMinor(stale.net_balance, currency)} has been outstanding since ${friendlyDate(stale.last_activity_at!)}.`,
      });
    }
  }

  // 4. The calm case is worth saying out loud too.
  if (insights.length === 0 && summary.people_with_balance === 0 && summary.people_count > 0) {
    insights.push({
      tone: 'neutral',
      title: 'Every account is settled',
      body: `All ${summary.people_count} accounts are square. ${formatMinor(summary.gross_settled, currency)} has been settled in total.`,
    });
  }

  return insights.slice(0, 3);
}

/* -------------------------------------------------------------------------- */

function TodayChip({
  children,
  tone,
  label,
}: {
  children: React.ReactNode;
  tone: 'receivable' | 'payable' | 'neutral';
  label: string;
}) {
  return (
    <span
      className={cn(
        'tnum inline-flex items-center gap-1 rounded-full border px-2.5 py-1 font-medium',
        tone === 'receivable' && 'border-receivable-line bg-receivable-soft text-receivable',
        tone === 'payable' && 'border-payable-line bg-payable-soft text-payable',
        tone === 'neutral' && 'border-line bg-sunken text-ink-muted',
      )}
    >
      {children}
      <span className="font-normal opacity-70">{label}</span>
    </span>
  );
}

function StatCard({
  id,
  tone,
  icon,
  label,
  caption,
  amount,
  currency,
  footnote,
  trend,
  goodWhenUp,
}: {
  id: string;
  tone: 'receivable' | 'payable' | 'neutral';
  icon: React.ReactNode;
  label: string;
  caption: string;
  amount: number;
  currency: string;
  footnote: string;
  trend: Trend;
  goodWhenUp: boolean;
}) {
  return (
    <Card className="lift h-full p-5">
      <div className="flex items-center gap-2">
        <span
          className={cn(
            'grid size-6 place-items-center rounded-md border',
            tone === 'receivable' && 'border-receivable-line bg-receivable-soft text-receivable',
            tone === 'payable' && 'border-payable-line bg-payable-soft text-payable',
            tone === 'neutral' && 'border-line-strong bg-sunken text-ink-muted',
          )}
        >
          {icon}
        </span>
        <p className="stat-label">{label}</p>
      </div>

      <div className="mt-3 flex items-end justify-between gap-4">
        <div className="min-w-0">
          <p className="money-lg truncate">
            <Money minor={amount} currency={currency} tone={tone} />
          </p>
          <p className="stat-note mt-1">{caption}</p>
          {/* On a phone this card is half a screen wide; the count belongs
              here rather than in a footer row that would not fit. */}
          <p className="mt-1 text-[0.75rem] text-ink-faint md:hidden">{footnote}</p>
        </div>
        <div className="hidden w-24 shrink-0 md:block lg:w-32">
          {/* Settled money is not a direction, so its line takes the brand
              accent rather than a money colour (§3). */}
          <Sparkline id={id} points={trend.points} tone={tone === 'neutral' ? 'accent' : tone} />
        </div>
      </div>

      <div className="mt-4 hidden items-center justify-between gap-3 border-t border-line pt-2.5 md:flex">
        <TrendChip
          changePercent={trend.changePercent}
          goodWhenUp={goodWhenUp}
          suffix="vs prior 15 days"
        />
        <span className="text-[0.75rem] text-ink-faint">{footnote}</span>
      </div>
    </Card>
  );
}

function SectionBar({
  title,
  href,
  linkLabel,
}: {
  title: string;
  href: string;
  linkLabel: string;
}) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-line px-5 py-3.5">
      <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
        {title}
      </h2>
      <Link
        href={href}
        className="group flex items-center gap-1 text-[0.75rem] font-medium text-ink-muted transition-colors duration-[var(--dur)] hover:text-accent"
      >
        {linkLabel}
        <ArrowRightIcon className="size-3.5 transition-transform duration-[var(--dur)] ease-[var(--ease)] group-hover:translate-x-0.5" />
      </Link>
    </div>
  );
}

/** A person and where they stand — the balance is the anchor (context.md §5). */
function BalanceRow({ person, currency }: { person: DashboardPeopleRow; currency: string }) {
  return (
    <Link
      href={`/people/${person.person_id}`}
      className="group flex items-center gap-3 px-4 py-3 transition-colors duration-[var(--dur)] ease-[var(--ease)] hover:bg-sunken sm:px-5"
    >
      <Avatar identity={person.name}>{initials(person.name)}</Avatar>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[0.875rem] font-medium text-ink">{person.name}</span>
        <span className="flex min-w-0 items-center gap-1.5 text-[0.75rem] text-ink-faint">
          {/* The account's own currency, when it is not the workspace's. A
              multi-currency ledger where a row does not say what it is
              denominated in is a ledger you have to click to read (§8). */}
          {person.currency && person.currency !== currency ? (
            <span className="shrink-0 rounded border border-line-strong bg-sunken px-1 py-px text-[0.6875rem] font-medium text-ink-muted">
              {person.currency}
            </span>
          ) : null}
          <span className="truncate">
            {person.last_activity_at ? friendlyDate(person.last_activity_at) : 'No activity yet'}
          </span>
        </span>
      </span>
      <NetBadge
        netMinor={person.net_balance}
        currency={person.currency ?? currency}
        approxMinor={person.net_balance_base}
        approxCurrency={currency}
      />
      <ArrowRightIcon className="size-4 shrink-0 text-ink-faint/60 transition-transform duration-[var(--dur)] ease-[var(--ease)] group-hover:translate-x-0.5 group-hover:text-ink-muted" />
    </Link>
  );
}
