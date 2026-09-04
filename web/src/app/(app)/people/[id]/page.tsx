import { notFound } from 'next/navigation';
import Link from 'next/link';
import type { Metadata } from 'next';
import { getMe } from '@/lib/supabase/server';
import { getPersonPage } from '@/lib/queries';
import {
  Avatar,
  Badge,
  Card,
  EmptyState,
  Panel,
  cn,
  segmentClass,
  SEGMENT_GROUP,
} from '@/components/ui/primitives';
import { CurrencyBreakdown, Money } from '@/components/money';
import { CountUp } from '@/components/motion/count-up';
import { SparklineFigure } from '@/components/charts/sparkline';
import { Reveal } from '@/components/motion/reveal';
import { initials } from '@/lib/names';
import { PersonActionBar } from './person-action-bar';
import { Timeline } from './timeline';
import { OpeningBalanceCard } from '@/components/ledger/opening-balance';
import { StatementButton } from './statement-button';
import { balanceTone, formatApprox, formatMoney } from '@/lib/money';
import { currencyLabel } from '@/lib/currencies';
import { personBalanceSeries } from '@/lib/series';
import { fullDate, relativeTime } from '@/lib/dates';
import { ArrowRightIcon, SettleIcon, WalletIcon } from '@/components/icons';
import type {
  CurrencyHalfBreakdown,
  OpenTransaction,
  OpeningHistoryEntry,
  Person,
  PersonBalance,
  PersonOpening,
  PositionSplit,
  TimelineEntry,
} from '@/lib/types';

/** Everything a `<Timeline>` needs besides the rows it is drawing. */
interface TimelineProps {
  person: Person;
  balance: PersonBalance;
  openTransactions: OpenTransaction[];
  currency: string;
}

/**
 * How many entries one server page of this account holds.
 *
 * Every tab reads from the same window, so the pagination controls mean one
 * thing rather than four. 150 is generous enough that the Settlements tab is
 * almost never truncated on a real account, and light enough that the window
 * renders without the page feeling assembled — a timeline row is a list item,
 * not a card.
 */
const WINDOW = 150;
/** How many transactions the Overview previews before handing over to its tab. */
const PREVIEW = 5;

type Tab = 'overview' | 'transactions' | 'settlements' | 'activity';
const TABS: Tab[] = ['overview', 'transactions', 'settlements', 'activity'];

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
 * v1.11.0 rebuilt this screen. It was the product's most important page and its
 * least designed one: everything the account knew was stacked into the first
 * viewport — cash in hand, the opening balance, the account position, a
 * sparkline, nine controls, four figures, two per-currency tables and an
 * opening-balance panel — before the history it is all evidence for even began.
 * A reader who wanted "where do we stand?" had to scroll past the answer's
 * working to find the answer.
 *
 * The shape now is the one a statement has:
 *
 *   1. Who, and where we stand — one figure, in words and in colour, with the
 *      one action that changes it. Nothing else competes for the first screen.
 *   2. Four tabs, because an account is four different questions and a reader
 *      only ever has one of them at a time:
 *
 *        Overview      what the position is made of, and the last few entries
 *        Transactions  credits, debits and transfers
 *        Settlements   money that actually moved
 *        Activity      everything, in order, including the opening book
 *
 *   3. Everything secondary — per-currency breakdowns, the opening book's own
 *      tables, the account's details — behind a disclosure inside Overview,
 *      open on demand and closed by default.
 *
 * The tabs are links, not state. The whole screen is server-rendered, so
 * switching tabs ships no JavaScript, survives a refresh, and is a real URL
 * that can be shared and bookmarked.
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
  const tab: Tab = TABS.includes(query.tab as Tab) ? (query.tab as Tab) : 'overview';

  const [me, data] = await Promise.all([
    getMe(),
    getPersonPage(id, WINDOW, pageIndex * WINDOW),
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
  const {
    person,
    balance,
    timeline,
    timeline_total: total,
    open_transactions: openTxns,
  } = data;
  // The opening balance is served in its own key since db/migrations/0019 and
  // is deliberately absent from `timeline`. Defaulted here so a client pointed
  // at a database that has not run that migration renders the page it always
  // did rather than throwing on a missing key.
  const opening = data.opening ?? null;
  const openingHistory = data.opening_history ?? [];
  const openingActivity = data.opening_activity ?? [];
  // The two halves the page shows separately (db/migrations/0022). `regular` is
  // cash in hand — the trading position with the opening balance taken out —
  // and `opening_position` is the opening book's own. Both are stated by the
  // database so nothing here subtracts one from the other. Defaulted for a
  // database that has not run 0022, where the whole position is all there is.
  const regular = data.regular ?? {
    currency,
    base_currency: baseCurrency,
    position: balance.net_balance,
    position_base: balance.net_balance_base,
    receivable: balance.outstanding_receivable,
    payable: balance.outstanding_payable,
    settled: balance.total_settled,
    credit: balance.total_credit,
    debit: balance.total_debit,
  };
  const openingPosition = data.opening_position ?? {
    currency,
    base_currency: baseCurrency,
    position: 0,
    position_base: null,
    receivable: 0,
    payable: 0,
    settled: 0,
    credit: 0,
    debit: 0,
    entry_count: 0,
  };
  const hasOpening = (openingPosition.entry_count ?? 0) > 0 || balance.opening_minor !== 0;
  const tone = balanceTone(regular.position);

  // Per-currency breakdown (db/migrations/0024). Worth showing only when this
  // account has traded in more than one currency, or in a single currency that
  // is not its ledger denomination — otherwise the headline already IS the
  // original figure.
  const regularCurrencyRows = (data.regular_by_currency ?? []).filter(
    (row) => row.credit !== 0 || row.debit !== 0 || row.settled !== 0,
  );
  const openingCurrencyRows = (data.opening_by_currency ?? []).filter(
    (row) => row.credit !== 0 || row.debit !== 0 || row.settled !== 0,
  );
  const showRegularByCurrency =
    regularCurrencyRows.length > 1 ||
    (regularCurrencyRows.length === 1 && regularCurrencyRows[0]!.currency !== currency);
  const showOpeningByCurrency =
    openingCurrencyRows.length > 1 ||
    (openingCurrencyRows.length === 1 && openingCurrencyRows[0]!.currency !== currency);

  const hasMore = (pageIndex + 1) * WINDOW < total;
  const series = personBalanceSeries(timeline, balance);
  const firstName = person.name.split(' ')[0];

  // The two halves of the window. `entry_kind` is stated by the database, so
  // neither list is inferred from a shape.
  const transactions = timeline.filter((entry) => entry.entry_kind === 'transaction');
  const settlements = timeline.filter((entry) => entry.entry_kind === 'settlement');

  const tabHref = (next: Tab) =>
    `/people/${person.id}?tab=${next}${pageIndex > 0 ? `&page=${pageIndex}` : ''}`;
  const pageHref = (next: number) =>
    `/people/${person.id}?tab=${tab}${next > 0 ? `&page=${next}` : ''}`;

  const timelineProps: TimelineProps = {
    person,
    balance,
    openTransactions: openTxns,
    currency,
  };

  const positionCaption =
    tone === 'receivable'
      ? `${firstName} owes you`
      : tone === 'payable'
        ? `You owe ${firstName}`
        : 'Everything is settled';

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
      {/* The account, in one screen: who, where we stand, what to do          */}
      {/* ------------------------------------------------------------------ */}
      <Reveal>
        <Panel>
          <header className="flex flex-wrap items-start gap-x-4 gap-y-3 px-5 pt-5 sm:px-6 sm:pt-6">
            <Avatar size="lg" identity={person.name}>
              {initials(person.name)}
            </Avatar>
            <div className="min-w-0 flex-1">
              <div className="flex flex-wrap items-center gap-2">
                <h1 className="page-title min-w-0 break-words">{person.name}</h1>
                {person.is_archived ? <Badge tone="muted">Archived</Badge> : null}
                {/* Stated always, not only when it differs from the base: "how
                    much is this in?" is the first question on a multi-currency
                    ledger, and a badge that appears and disappears is a worse
                    answer than one that is simply always there. */}
                <Badge tone="muted">{currency}</Badge>
                {/* Only when they differ. A person who has never switched has
                    one currency and should be told about exactly one. */}
                {currencySwitched ? (
                  <Badge tone="muted">New entries in {defaultCurrency}</Badge>
                ) : null}
              </div>
              {/* One metadata line, not three. Type, status and when this
                  account was last touched — the three things that qualify a
                  name. Phone and email moved into Overview's details, where
                  they are looked up rather than read. */}
              <p className="mt-1 text-[0.8125rem] text-ink-muted">
                <span className="capitalize">{person.type}</span>
                {' · '}
                {person.is_archived ? 'Archived' : 'Active'}
                {balance.last_activity_at
                  ? ` · Last activity ${relativeTime(balance.last_activity_at)}`
                  : ' · No activity yet'}
              </p>
            </div>

            {/* The state as a word, at the top right, where a statement puts
                it. Colour alone never carries meaning here (§29). */}
            <Badge
              tone={tone === 'receivable' ? 'receivable' : tone === 'payable' ? 'payable' : 'neutral'}
              className="uppercase tracking-wider"
            >
              {tone === 'receivable' ? 'Receivable' : tone === 'payable' ? 'Payable' : 'Settled'}
            </Badge>
          </header>

          {/* The one figure this screen is about. Centred, alone, and given the
              room to be read across a desk — everything that explains it is one
              tab away rather than one line below. */}
          <div className="px-5 py-7 text-center sm:px-6 sm:py-9">
            <p
              className={cn(
                'money-hero',
                tone === 'receivable' && 'text-receivable',
                tone === 'payable' && 'text-payable',
                tone === 'settled' && 'text-ink',
              )}
            >
              {/* Animates when it changes — which is exactly when a settlement
                  has just been recorded on this page. */}
              <CountUp minor={Math.abs(regular.position)} currency={currency} />
            </p>
            <p
              className={cn(
                'mt-2 text-[0.9375rem] font-medium',
                tone === 'receivable' && 'text-receivable',
                tone === 'payable' && 'text-payable',
                tone === 'settled' && 'text-ink-muted',
              )}
            >
              {positionCaption}
            </p>

            {/* The same position in the workspace's currency. Shown only when
                there is another currency to show, and labelled as an
                approximation at today's rate, because that is what it is —
                nothing settles against this figure. */}
            {currency !== baseCurrency && regular.position !== 0 ? (
              <p className="mt-1.5 text-[0.8125rem] text-ink-faint">
                {regular.position_base === null
                  ? `No ${currency} → ${baseCurrency} rate yet`
                  : `${formatApprox(Math.abs(regular.position_base), baseCurrency)} at today’s rate`}
              </p>
            ) : null}

            {/* Cash in hand is the headline; if this account also carries an
                opening balance, the fact is stated here in one line and the
                figures live in Overview. A second number beside the first is
                how the old header started becoming a dashboard. */}
            {hasOpening ? (
              <p className="mt-3 text-[0.75rem] text-ink-faint">
                Cash in hand. An opening balance of{' '}
                <span className="tnum text-ink-muted">
                  {formatMoney(Math.abs(openingPosition.position), currency, { base: currency })}
                </span>{' '}
                is accounted separately —{' '}
                <Link
                  href={tabHref('overview')}
                  className="text-accent underline-offset-2 hover:underline"
                >
                  see Overview
                </Link>
                .
              </p>
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
        </Panel>
      </Reveal>

      {/* ------------------------------------------------------------------ */}
      {/* Four questions, one at a time                                       */}
      {/* ------------------------------------------------------------------ */}
      <nav
        // Horizontally scrollable rather than wrapped: four segments at a
        // readable size do not fit 375px, and a segmented control that breaks
        // onto two lines stops reading as one control.
        className="mt-6 -mx-4 overflow-x-auto px-4 no-scrollbar sm:mx-0 sm:px-0"
        aria-label="Account sections"
      >
        <div className={cn(SEGMENT_GROUP, 'w-max')}>
          {TABS.map((value) => (
            <Link
              key={value}
              href={tabHref(value)}
              scroll={false}
              aria-current={tab === value ? 'page' : undefined}
              className={cn(segmentClass(tab === value), 'capitalize')}
            >
              {value}
            </Link>
          ))}
        </div>
      </nav>

      <section className="mt-4">
        {tab === 'overview' ? (
          <Overview
            currency={currency}
            baseCurrency={baseCurrency}
            regular={regular}
            tone={tone}
            series={series}
            windowSize={Math.min(timeline.length, WINDOW)}
            transactions={transactions.slice(0, PREVIEW)}
            transactionCount={transactions.length}
            timelineProps={timelineProps}
            person={person}
            balance={balance}
            opening={opening}
            openingHistory={openingHistory}
            openingActivity={openingActivity}
            openingPosition={openingPosition}
            hasOpening={hasOpening}
            regularCurrencyRows={showRegularByCurrency ? regularCurrencyRows : []}
            openingCurrencyRows={showOpeningByCurrency ? openingCurrencyRows : []}
            moreHref={tabHref('transactions')}
          />
        ) : tab === 'transactions' ? (
          <TabPane
            title="Transactions"
            note="Credits, debits and transfers. Settlements are on their own tab; the opening balance is not a transaction and is not in this list."
            action={<StatementButton personId={person.id} personName={person.name} />}
          >
            {transactions.length > 0 ? (
              <Timeline entries={transactions} {...timelineProps} />
            ) : (
              <Card>
                <EmptyState
                  icon={<WalletIcon />}
                  title="No transactions here"
                  description="Credits and debits you record with this account will appear on this tab."
                />
              </Card>
            )}
          </TabPane>
        ) : tab === 'settlements' ? (
          <TabPane
            title="Settlements"
            note="Money that actually changed hands, and what it closed."
          >
            {settlements.length > 0 ? (
              <Timeline entries={settlements} {...timelineProps} />
            ) : (
              <Card>
                <EmptyState
                  icon={<SettleIcon />}
                  title="Nothing settled yet"
                  description={
                    balance.outstanding_receivable > 0 || balance.outstanding_payable > 0
                      ? `Settle with ${firstName} and the record will appear here.`
                      : 'Settlements you record against this account will appear here.'
                  }
                />
              </Card>
            )}
          </TabPane>
        ) : (
          <TabPane
            title="Activity"
            note="Every entry on this account in the order it happened, including the opening book."
          >
            {timeline.length > 0 || openingActivity.length > 0 ? (
              <div className="space-y-6">
                <Timeline entries={timeline} {...timelineProps} />
                {openingActivity.length > 0 ? (
                  <div>
                    <h3 className="stat-label mb-2 px-1">Against the opening balance</h3>
                    <Timeline entries={openingActivity} {...timelineProps} />
                  </div>
                ) : null}
              </div>
            ) : (
              <Card>
                <EmptyState
                  icon={<WalletIcon />}
                  title="Nothing has happened yet"
                  description="Everything you record with this account will show up here."
                />
              </Card>
            )}
          </TabPane>
        )}

        {/* One set of pagination controls, moving one window, shared by every
            tab — so "Older" means the same thing wherever the reader is. */}
        {tab !== 'overview' && (hasMore || pageIndex > 0) ? (
          <div className="mt-5 flex items-center justify-between gap-4">
            {pageIndex > 0 ? (
              <PageLink href={pageHref(pageIndex - 1)}>← Newer</PageLink>
            ) : (
              <span />
            )}
            <span className="text-[0.75rem] text-ink-faint tnum">
              {pageIndex * WINDOW + 1}–{Math.min((pageIndex + 1) * WINDOW, total)} of {total}
            </span>
            {hasMore ? <PageLink href={pageHref(pageIndex + 1)}>Older →</PageLink> : <span />}
          </div>
        ) : null}
      </section>
    </div>
  );
}

/* -------------------------------------------------------------------------- */

/** A tab's heading, its one line of explanation, and whatever it holds. */
function TabPane({
  title,
  note,
  action,
  children,
}: {
  title: string;
  note: string;
  action?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <Reveal>
      <div className="mb-3 flex flex-wrap items-start justify-between gap-3 px-1">
        <div className="min-w-0">
          <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
            {title}
          </h2>
          <p className="mt-0.5 max-w-prose text-[0.75rem] leading-relaxed text-ink-faint">{note}</p>
        </div>
        {action ? <div className="shrink-0">{action}</div> : null}
      </div>
      {children}
    </Reveal>
  );
}

/**
 * Overview — what the headline is made of.
 *
 * The order is the order the questions are asked in: the four figures behind
 * the position, then how it got there, then the last few entries, and only then
 * the material a reader has to go looking for.
 */
function Overview({
  currency,
  baseCurrency,
  regular,
  tone,
  series,
  windowSize,
  transactions,
  transactionCount,
  timelineProps,
  person,
  balance,
  opening,
  openingHistory,
  openingActivity,
  openingPosition,
  hasOpening,
  regularCurrencyRows,
  openingCurrencyRows,
  moreHref,
}: {
  currency: string;
  baseCurrency: string;
  regular: { credit: number; debit: number; settled: number; receivable: number; payable: number };
  tone: 'receivable' | 'payable' | 'settled';
  series: number[] | null;
  windowSize: number;
  transactions: TimelineEntry[];
  transactionCount: number;
  timelineProps: TimelineProps;
  person: Person;
  balance: PersonBalance;
  opening: PersonOpening | null;
  openingHistory: OpeningHistoryEntry[];
  openingActivity: TimelineEntry[];
  openingPosition: PositionSplit;
  hasOpening: boolean;
  regularCurrencyRows: CurrencyHalfBreakdown[];
  openingCurrencyRows: CurrencyHalfBreakdown[];
  moreHref: string;
}) {
  return (
    <div className="space-y-4">
      {/* The four figures the position is made of. On a hairline grid rather
          than in four cards: they are one statement read across, not four
          things (craft floor — cards only where elevation means something). */}
      <Reveal>
        <Card className="overflow-hidden">
          <div className="grid grid-cols-2 divide-line sm:grid-cols-4 sm:divide-x">
            {/* Credit is what they gave you, so it is what you owe. The
                engine's total_credit counts the other direction — the mapping
                lives in lib/direction.ts and nowhere else. */}
            <Figure
              label="Credited to you"
              minor={regular.debit}
              currency={currency}
              tone={regular.debit > 0 ? 'payable' : 'neutral'}
            />
            <Figure
              label="Debited to them"
              minor={regular.credit}
              currency={currency}
              tone={regular.credit > 0 ? 'receivable' : 'neutral'}
            />
            <Figure label="Settled" minor={regular.settled} currency={currency} tone="neutral" />
            <Figure
              label={tone === 'payable' ? 'You will pay' : 'You will receive'}
              minor={tone === 'payable' ? regular.payable : regular.receivable}
              currency={currency}
              tone={tone === 'payable' ? 'payable' : tone === 'settled' ? 'neutral' : 'receivable'}
            />
          </div>

          {/* How the position moved, against zero — the crossing between owed
              to you and owed by you is the only event this line is about. */}
          {series ? (
            <div className="border-t border-line px-5 py-4 sm:px-6">
              <SparklineFigure
                id="person"
                label="Balance"
                points={series}
                tone={tone === 'payable' ? 'payable' : tone === 'settled' ? 'accent' : 'receivable'}
                currency={currency}
                caption={`Across the last ${windowSize} ${windowSize === 1 ? 'entry' : 'entries'}`}
                chartClassName="h-16"
              />
            </div>
          ) : null}
        </Card>
      </Reveal>

      {/* The opening balance, in its own section and never folded into the
          figure above. */}
      {hasOpening ? (
        <OpeningBalanceCard
          person={person}
          opening={opening}
          history={openingHistory}
          activity={openingActivity}
          position={openingPosition}
          currency={currency}
          baseCurrency={baseCurrency}
          openingMinor={balance.opening_minor}
        />
      ) : null}

      {/* The last few entries, so Overview answers "and what happened lately?"
          without becoming the Transactions tab. */}
      <Reveal>
        <div className="mb-2 flex items-baseline justify-between gap-3 px-1">
          <h2 className="stat-label">Recent transactions</h2>
          {transactionCount > transactions.length ? (
            <Link
              href={moreHref}
              className="inline-flex items-center gap-1 text-[0.75rem] font-medium text-accent transition-colors duration-[var(--dur)] hover:text-accent-hover"
            >
              All {transactionCount}
              <ArrowRightIcon className="size-3" />
            </Link>
          ) : null}
        </div>
        {transactions.length > 0 ? (
          <Timeline entries={transactions} {...timelineProps} />
        ) : (
          <Card>
            <EmptyState
              icon={<WalletIcon />}
              title="No transactions yet"
              description="Add a credit or a debit and it will appear here."
            />
          </Card>
        )}
      </Reveal>

      {/* ------------------------------------------------------------------ */}
      {/* Looked up, not read. Closed by default, and a real disclosure —     */}
      {/* <details> is keyboard operable, findable by the browser's own       */}
      {/* in-page search, and costs no JavaScript.                            */}
      {/* ------------------------------------------------------------------ */}
      <Reveal>
        <Disclosure summary="Account details" hint="Type, contact, totals">
          <dl className="divide-y divide-line">
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
              value={formatMoney(balance.total_credit + balance.total_debit, currency, {
                base: currency,
              })}
            />
            <Detail label="Status" value={person.is_archived ? 'Archived' : 'Active'} />
          </dl>
          {person.notes ? (
            <div className="border-t border-line px-5 py-4">
              <p className="stat-label mb-1.5">Notes</p>
              <p className="whitespace-pre-wrap text-[0.875rem] leading-relaxed text-ink-muted">
                {person.notes}
              </p>
            </div>
          ) : null}
        </Disclosure>
      </Reveal>

      {regularCurrencyRows.length > 0 ? (
        <Reveal>
          <Disclosure
            summary="Cash in hand by currency"
            hint={`${regularCurrencyRows.length} currencies`}
          >
            <p className="border-b border-line px-5 py-3 text-[0.75rem] text-ink-faint">
              The original amounts entered for this account, kept in their own currency.
            </p>
            <CurrencyBreakdown rows={regularCurrencyRows} baseCurrency={currency} kind="cash" />
          </Disclosure>
        </Reveal>
      ) : null}

      {openingCurrencyRows.length > 0 ? (
        <Reveal>
          <Disclosure
            summary="Opening balance by currency"
            hint={`${openingCurrencyRows.length} currencies`}
          >
            <p className="border-b border-line px-5 py-3 text-[0.75rem] text-ink-faint">
              What this account was carried in with, per currency, less whatever has settled.
            </p>
            <CurrencyBreakdown rows={openingCurrencyRows} baseCurrency={currency} kind="opening" />
          </Disclosure>
        </Reveal>
      ) : null}
    </div>
  );
}

/**
 * A closed-by-default section.
 *
 * Native `<details>`, so it is keyboard operable, announced correctly, found by
 * the browser's own in-page search even while closed, and free of JavaScript.
 * The marker is drawn rather than inherited — the platform triangle is the one
 * part of the element that never matches a design system.
 */
function Disclosure({
  summary,
  hint,
  children,
}: {
  summary: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <details className="group overflow-hidden rounded-card border border-line bg-surface shadow-[var(--shadow-card)]">
      <summary
        className={cn(
          'flex cursor-pointer list-none items-center gap-3 px-5 py-3.5',
          'transition-colors duration-[var(--dur)] ease-[var(--ease)] hover:bg-sunken',
          '[&::-webkit-details-marker]:hidden',
        )}
      >
        <span className="min-w-0 flex-1 font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
          {summary}
        </span>
        {hint ? <span className="shrink-0 text-[0.75rem] text-ink-faint">{hint}</span> : null}
        <ArrowRightIcon
          aria-hidden
          className="size-3.5 shrink-0 text-ink-faint transition-transform duration-[var(--dur)] ease-[var(--ease)] group-open:rotate-90 motion-reduce:transition-none"
        />
      </summary>
      <div className="border-t border-line">{children}</div>
    </details>
  );
}

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
      <p className="mt-1 text-[1rem] font-semibold">
        <Money minor={minor} currency={currency} base={currency} tone={tone} />
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
      <dt className="text-[0.8125rem] text-ink-muted">{label}</dt>
      <dd className={cn('truncate text-[0.8125rem] font-medium text-ink', className)}>{value}</dd>
    </div>
  );
}

function PageLink({ href, children }: { href: string; children: React.ReactNode }) {
  return (
    <Link
      href={href}
      className="tap rounded-field border border-line bg-surface px-3 py-1.5 text-[0.8125rem] font-medium text-ink-muted transition-[color,border-color] duration-[var(--dur)] hover:border-line-strong hover:text-ink"
    >
      {children}
    </Link>
  );
}
