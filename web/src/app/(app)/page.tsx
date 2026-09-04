import Link from 'next/link';
import { getActivitySummary, getDashboard } from '@/lib/queries';
import {
  Avatar,
  Card,
  CardHeader,
  EmptyState,
  buttonClass,
  cn,
} from '@/components/ui/primitives';
import { CurrencyBreakdown, Money, NetBadge, SplitBar } from '@/components/money';
import { ActivityChart } from '@/components/charts/activity-chart';
import { Sparkline, SparklineFigure, TrendChip } from '@/components/charts/sparkline';
import { ActivityRow } from '@/components/ledger/activity-row';
import { AddTransactionButton } from '@/components/ledger/add-transaction-button';
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
import { balanceTone, formatApprox, formatMoney } from '@/lib/money';
import { trendsFromBuckets, type Trend } from '@/lib/series';
import type {
  CurrencyHalfBreakdown,
  CurrencyTotals,
  Dashboard,
  DashboardPeopleRow,
  WorkspacePosition,
} from '@/lib/types';

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
  const {
    summary,
    profile,
    today,
    people_with_balance: people,
    cash_in_hand: cashInHand,
    opening: openingTotal,
    totals_by_currency: byCurrency,
  } = data;
  // Absent against a database that has not run 0022; the card is simply not
  // drawn there, exactly as the currency card was not drawn before 0015.
  const hasOpening =
    Boolean(openingTotal) &&
    (openingTotal.position !== 0 || openingTotal.people_count > 0);
  // The per-currency breakdown behind each half (db/migrations/0024). Present
  // once the database has run 0024; before it, these are empty and the card
  // falls back to the base-currency-only blocks below.
  const cashRows = byCurrency
    .map((row) => row.cash)
    .filter((row): row is CurrencyHalfBreakdown => Boolean(row));
  const openingRows = byCurrency
    .map((row) => row.opening)
    .filter((row): row is CurrencyHalfBreakdown => Boolean(row));
  const hasCurrencyBreakdown = cashRows.some(
    (row) => row.credit !== 0 || row.debit !== 0 || row.settled !== 0,
  );
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
          <h1 className="page-title mt-0.5">
            Here’s your money overview
          </h1>
        </div>

        {today.count > 0 ? (
          <div className="flex flex-wrap items-center gap-2 text-[0.75rem]">
            <span className="text-ink-faint">Today</span>
            {today.credit > 0 ? (
              <TodayChip tone="receivable" label="receivable">
                {formatMoney(today.credit, currency, { base: currency })}
              </TodayChip>
            ) : null}
            {today.debit > 0 ? (
              <TodayChip tone="payable" label="payable">
                {formatMoney(today.debit, currency, { base: currency })}
              </TodayChip>
            ) : null}
            {today.settled > 0 ? (
              <TodayChip tone="neutral" label="settled">
                {formatMoney(today.settled, currency, { base: currency })}
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

              <p className="money-hero mt-2.5">
                <Money
                  minor={Math.abs(net)}
                  currency={currency}
                  base={currency}
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

            {/* The net position over the window, drawn against zero rather than
                against its own floor: on this series the only event worth
                seeing is the crossing between owed-to-you and owed-by-you, and
                a line scaled to its own minimum hides exactly that. */}
            <div className="flex min-w-0 flex-1 justify-end">
              <SparklineFigure
                id="net"
                label="Last 30 days"
                points={trends.net.points}
                tone={netTone === 'payable' ? 'payable' : netTone === 'settled' ? 'accent' : 'receivable'}
                currency={currency}
                caption="Net position, daily"
                className="w-full max-w-[16rem]"
                chartClassName="h-14"
              />
            </div>
          </div>

          {summary.total_receivable > 0 && summary.total_payable > 0 ? (
            <div className="mt-5 border-t border-line pt-3">
              <SplitBar receivable={summary.total_receivable} payable={summary.total_payable} />
              <p className="mt-2 flex items-center justify-between text-[0.75rem]">
                <span className="text-receivable">
                  Receivable {formatMoney(summary.total_receivable, currency, { base: currency })}
                </span>
                <span className="text-payable">
                  Payable {formatMoney(summary.total_payable, currency, { base: currency })}
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
      {/* Cash in hand, and the opening balance beside it (0022)              */}
      {/*                                                                     */}
      {/* This card replaced "By currency". The per-currency breakdown         */}
      {/* answered a question about presentation — the same money before it    */}
      {/* was converted — and this one answers a question about the ledger:    */}
      {/* how much of the position is trading, and how much is what the        */}
      {/* accounts were carried in with. The two figures are calculated        */}
      {/* independently by the database and are never added together here.     */}
      {/* ------------------------------------------------------------------ */}
      {cashInHand ? (
        <Reveal delay={145} className="mt-4 block">
          <Card className="overflow-hidden">
            <CardHeader
              title="Cash in hand"
              description={
                hasOpening
                  ? `The regular trading position across every account, in the currency each amount was entered in. The opening balances are counted separately below and are not part of this figure.`
                  : `The regular trading position across every account, in the currency each amount was entered in.`
              }
            />

            {hasCurrencyBreakdown ? (
              <>
                <CurrencyBreakdown rows={cashRows} baseCurrency={currency} kind="cash" />
                <TotalLine position={cashInHand} currency={currency} />
                {hasOpening ? (
                  <>
                    <div className="border-t border-line-strong px-4 pt-4 sm:px-5">
                      <p className="text-[0.6875rem] font-semibold uppercase tracking-wide text-ink-faint">
                        Opening balance
                      </p>
                      <p className="mt-1 text-[0.75rem] leading-relaxed text-ink-faint">
                        What the accounts were carried in with, less whatever has been settled
                        against it. Independently calculated, never part of cash in hand.
                      </p>
                    </div>
                    <CurrencyBreakdown rows={openingRows} baseCurrency={currency} kind="opening" />
                    <TotalLine position={openingTotal} currency={currency} />
                  </>
                ) : null}
              </>
            ) : (
              <div className="divide-y divide-line">
                <WorkspacePositionBlock
                  label="Cash in hand"
                  position={cashInHand}
                  currency={currency}
                  originals={originalsOf(byCurrency, currency, false)}
                />
                {hasOpening ? (
                  <WorkspacePositionBlock
                    label="Opening balance"
                    position={openingTotal}
                    currency={currency}
                    originals={originalsOf(byCurrency, currency, true)}
                    caption="What the accounts were carried in with, less whatever has been settled against it. Independently calculated."
                  />
                ) : null}
              </div>
            )}
          </Card>
        </Reveal>
      ) : null}

      {/* ------------------------------------------------------------------ */}
      {/* The month in flows (upgrade §8)                                     */}
      {/* ------------------------------------------------------------------ */}
      {buckets.length > 1 ? (
        <Reveal delay={150} className="mt-4 block">
          <Card className="overflow-hidden">
            <CardHeader
              title="Last 30 days"
              description="What moved each day. Hover or tap a column for that day."
            />
            <div className="px-5 py-5">
              <ActivityChart buckets={buckets} currency={currency} />
            </div>
          </Card>
        </Reveal>
      ) : null}

      {/* ------------------------------------------------------------------ */}
      {/* Who, what just happened, what it means, and what to do next         */}
      {/*                                                                     */}
      {/* Two columns that flow independently, not two rows of two cards.     */}
      {/* As two rows, a short card on the left (one outstanding balance)     */}
      {/* against a long one on the right (six activity rows) stranded ~400px */}
      {/* of nothing between it and the card below — the dashboard's largest  */}
      {/* dead zone, and one that grew as the ledger got quieter. Stacking    */}
      {/* each column lets the left pair close up against itself.             */}
      {/* ------------------------------------------------------------------ */}
      <div className="mt-4 grid items-start gap-4 lg:grid-cols-[1.05fr_1fr]">
        <div className="grid gap-4">
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
          <Card className="overflow-hidden">
            <div className="border-b border-line px-5 py-3.5">
              <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                Quick actions
              </h2>
            </div>
            <QuickActions currency={currency} />
          </Card>
        </Reveal>
        </div>

        <div className="grid gap-4">
        <Reveal delay={180}>
          <Card className="overflow-hidden">
            <SectionBar title="Recent activity" href="/activity" linkLabel="View all" />

            {activity.length === 0 ? (
              <EmptyState
                icon={<ActivityIcon />}
                title="No transactions yet"
                description="Record one and it will appear here straight away."
                action={<AddTransactionButton currency={currency} />}
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
        body: `${formatMoney(top.net_balance, currency, { base: currency })} of the ${formatMoney(summary.total_receivable, currency, { base: currency })} owed to you sits with one account. Worth chasing first.`,
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
      body: `${formatMoney(trends.credit.total, currency, { base: currency })} of debits in the last 30 days, ${up ? 'more' : 'less'} in the recent half of that window than the earlier half.`,
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
        body: `${formatMoney(stale.net_balance, currency, { base: currency })} has been outstanding since ${friendlyDate(stale.last_activity_at!)}.`,
      });
    }
  }

  // 4. The calm case is worth saying out loud too.
  if (insights.length === 0 && summary.people_with_balance === 0 && summary.people_count > 0) {
    insights.push({
      tone: 'neutral',
      title: 'Every account is settled',
      body: `All ${summary.people_count} accounts are square. ${formatMoney(summary.gross_settled, currency, { base: currency })} has been settled in total.`,
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
          <p className="money-lg">
            <Money minor={amount} currency={currency} base={currency} tone={tone} />
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

/**
 * One of the two workspace totals, with its own receivable / payable / settled
 * / today (db/migrations/0022).
 *
 * The rule this block exists to make visible: **cash in hand never contains an
 * opening balance**. Both figures are summed by the database from their own
 * half of the ledger, and the only place they are added together is the
 * position card above — which says so.
 */
/**
 * The original figures behind a converted total, as one line.
 *
 * A total in the workspace currency only exists because the dirhams were
 * converted into rupees first; this says what they were before that step. Rows
 * in the workspace currency are left out — the headline already is that figure,
 * and repeating it would say nothing.
 */
function originalsOf(
  totals: CurrencyTotals[],
  baseCurrency: string,
  opening: boolean,
): string | undefined {
  const parts: string[] = [];
  for (const row of totals) {
    if (row.currency === baseCurrency) continue;
    const minor = (opening ? row.opening_net_position : row.cash_net_position) ?? 0;
    if (minor === 0) continue;
    parts.push(formatMoney(Math.abs(minor), row.currency));
  }
  return parts.length > 0 ? parts.join('  ·  ') : undefined;
}

/**
 * The consolidated figure for one half, in the workspace currency — shown
 * once, beneath the per-currency blocks, as the reference total. It is the
 * only converted number in the card and nothing settles against it.
 */
function TotalLine({
  position,
  currency,
}: {
  position: WorkspacePosition;
  currency: string;
}) {
  const tone = balanceTone(position.position);
  return (
    <div className="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-1 bg-sunken/50 px-4 py-3 sm:px-5">
      <span className="text-[0.6875rem] font-medium uppercase tracking-wide text-ink-faint">
        Total in {currency}
      </span>
      <span
        className={cn(
          'tnum text-[0.9375rem] font-semibold',
          tone === 'receivable' && 'text-receivable',
          tone === 'payable' && 'text-payable',
          tone === 'settled' && 'text-ink-muted',
        )}
      >
        ≈ {formatMoney(Math.abs(position.position), currency, { base: currency })}
      </span>
    </div>
  );
}

function WorkspacePositionBlock({
  label,
  position,
  currency,
  originals,
  caption,
}: {
  label: string;
  position: WorkspacePosition;
  currency: string;
  /**
   * The figures this total was converted from, in the currencies they were
   * entered in. Absent on a single-currency workspace, where the headline
   * already is the original.
   */
  originals?: string;
  caption?: string;
}) {
  const tone = balanceTone(position.position);

  return (
    <div className="px-4 py-4 sm:px-5">
      <p className="text-[0.6875rem] font-semibold uppercase tracking-wide text-ink-faint">
        {label}
      </p>
      <p
        className={cn(
          'tnum mt-1 text-[1.5rem] font-semibold leading-none',
          tone === 'receivable' && 'text-receivable',
          tone === 'payable' && 'text-payable',
          tone === 'settled' && 'text-ink-muted',
        )}
      >
        {formatMoney(Math.abs(position.position), currency, { base: currency })}
      </p>
      {originals ? (
        <p className="tnum mt-1 text-[0.75rem] text-ink-muted">from {originals}</p>
      ) : null}
      {caption ? (
        <p className="mt-1 text-[0.75rem] leading-relaxed text-ink-faint">{caption}</p>
      ) : null}

      <dl className="mt-3 grid grid-cols-2 gap-x-4 gap-y-2 sm:grid-cols-4">
        <PositionFigure label="Receivable" minor={position.receivable} currency={currency} tone="receivable" />
        <PositionFigure label="Payable" minor={position.payable} currency={currency} tone="payable" />
        <PositionFigure label="Settled" minor={position.settled} currency={currency} />
        <PositionFigure label="Today" minor={position.today} currency={currency} />
      </dl>
    </div>
  );
}

function PositionFigure({
  label,
  minor,
  currency,
  tone,
}: {
  label: string;
  minor: number;
  currency: string;
  tone?: 'receivable' | 'payable';
}) {
  return (
    <div className="min-w-0">
      <dt className="truncate text-[0.6875rem] text-ink-faint">{label}</dt>
      <dd
        className={cn(
          'tnum truncate text-[0.875rem] font-medium',
          tone === 'receivable' && 'text-receivable',
          tone === 'payable' && 'text-payable',
          !tone && 'text-ink-muted',
        )}
      >
        {formatMoney(minor, currency, { base: currency })}
      </dd>
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
        base={currency}
        approxMinor={person.net_balance_base}
        approxCurrency={currency}
      />
      <ArrowRightIcon className="size-4 shrink-0 text-ink-faint/60 transition-transform duration-[var(--dur)] ease-[var(--ease)] group-hover:translate-x-0.5 group-hover:text-ink-muted" />
    </Link>
  );
}
