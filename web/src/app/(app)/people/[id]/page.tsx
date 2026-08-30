import { notFound } from 'next/navigation';
import Link from 'next/link';
import type { Metadata } from 'next';
import { getMe } from '@/lib/supabase/server';
import { getPersonPage } from '@/lib/queries';
import { Avatar, Badge, Card, Panel, cn, segmentClass, SEGMENT_GROUP } from '@/components/ui/primitives';
import { CurrencyBreakdown, Money } from '@/components/money';
import { CountUp } from '@/components/motion/count-up';
import { Sparkline } from '@/components/charts/sparkline';
import { Reveal } from '@/components/motion/reveal';
import { initials } from '@/lib/names';
import { PersonActionBar } from './person-action-bar';
import { Timeline } from './timeline';
import { OpeningBalanceCard } from '@/components/ledger/opening-balance';
import { StatementButton } from './statement-button';
import { balanceTone, formatApprox, formatMoney } from '@/lib/money';
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
              <p className="text-[0.8125rem] font-medium text-ink-muted">Cash in hand</p>
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
                <CountUp minor={Math.abs(regular.position)} currency={currency} />
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
                  ? `${firstName} owes you, on regular activity`
                  : tone === 'payable'
                    ? `You owe ${firstName}, on regular activity`
                    : 'Regular activity is settled'}
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

              {/* The opening balance, stated as its own figure and never folded
                  into the one above. The account position is printed beside it
                  so the arithmetic is visible rather than implied — the reader
                  can see the two figures and their sum, and no number appears
                  twice inside another. */}
              {hasOpening ? (
                <div className="mt-4 flex flex-wrap gap-x-8 gap-y-3">
                  <SecondaryFigure
                    label="Opening balance"
                    minor={openingPosition.position}
                    currency={currency}
                    baseMinor={openingPosition.position_base}
                    baseCurrency={baseCurrency}
                    caption={
                      openingPosition.position === 0
                        ? 'Settled in full'
                        : openingPosition.position > 0
                          ? `${firstName} owed you this when the account opened`
                          : `You owed ${firstName} this when the account opened`
                    }
                  />
                  <SecondaryFigure
                    label="Account position"
                    minor={balance.net_balance}
                    currency={currency}
                    baseMinor={balance.net_balance_base}
                    baseCurrency={baseCurrency}
                    caption="Cash in hand and the opening balance together"
                    quiet
                  />
                </div>
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
            <Figure
              label="Settled"
              minor={regular.settled}
              currency={currency}
              tone="neutral"
            />
            <Figure
              label={tone === 'payable' ? 'You will pay' : 'You will receive'}
              minor={tone === 'payable' ? regular.payable : regular.receivable}
              currency={currency}
              tone={tone === 'payable' ? 'payable' : tone === 'settled' ? 'neutral' : 'receivable'}
            />
          </div>
        </Panel>
      </Reveal>

      {/* ------------------------------------------------------------------ */}
      {/* Cash in hand by the currency each amount was entered in (0024)      */}
      {/* ------------------------------------------------------------------ */}
      {showRegularByCurrency ? (
        <Reveal delay={55}>
          <Card className="mt-4 overflow-hidden">
            <div className="border-b border-line px-5 py-3.5">
              <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                Cash in hand by currency
              </h2>
              <p className="mt-0.5 text-[0.75rem] text-ink-faint">
                The original amounts entered for this account, kept in their own currency.
              </p>
            </div>
            <CurrencyBreakdown
              rows={regularCurrencyRows}
              baseCurrency={currency}
              kind="cash"
            />
          </Card>
        </Reveal>
      ) : null}

      {/* ------------------------------------------------------------------ */}
      {/* Opening balance — its own section, never a row in the history       */}
      {/* ------------------------------------------------------------------ */}
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

      {showOpeningByCurrency ? (
        <Reveal delay={55}>
          <Card className="mt-4 overflow-hidden">
            <div className="border-b border-line px-5 py-3.5">
              <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
                Opening balance by currency
              </h2>
              <p className="mt-0.5 text-[0.75rem] text-ink-faint">
                What this account was carried in with, per currency, less whatever has settled.
              </p>
            </div>
            <CurrencyBreakdown
              rows={openingCurrencyRows}
              baseCurrency={currency}
              kind="opening"
            />
          </Card>
        </Reveal>
      ) : null}

      {/* ------------------------------------------------------------------ */}
      {/* Regular transactions / details / notes                              */}
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
              {value === 'history'
                ? 'Transactions'
                : value === 'details'
                  ? 'Details'
                  : 'Notes'}
            </Link>
          ))}
        </div>

        {tab === 'history' ? (
          <>
            <div className="mb-2 flex flex-wrap items-center justify-between gap-3 px-1">
              <h2 className="text-[0.6875rem] font-semibold uppercase tracking-wider text-ink-faint">
                Regular transactions
              </h2>
              {/* Credits, debits, transfers and settlements. The opening
                  balance is not one of them and is not in this list. */}
              <StatementButton personId={person.id} personName={person.name} />
            </div>
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
              value={formatMoney(balance.total_credit + balance.total_debit, currency)}
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

/**
 * A figure that sits under the headline without competing with it.
 *
 * Used for the opening balance and the account position — two numbers the
 * reader needs beside cash in hand, and neither of which may be mistaken for
 * it. Smaller, labelled, and never animated: only the headline moves.
 */
function SecondaryFigure({
  label,
  minor,
  currency,
  caption,
  baseMinor,
  baseCurrency,
  quiet = false,
}: {
  label: string;
  minor: number;
  currency: string;
  caption: string;
  /**
   * The same figure in the workspace currency. Printed only when it says
   * something the figure above does not — that is, on an account kept in
   * another currency — and marked as the approximation it is.
   */
  baseMinor?: number | null;
  baseCurrency?: string;
  quiet?: boolean;
}) {
  return (
    <div className="min-w-0">
      <p className="text-[0.6875rem] font-semibold uppercase tracking-wide text-ink-faint">
        {label}
      </p>
      <p
        className={cn(
          'tnum mt-0.5 text-[1.0625rem] font-semibold',
          quiet && 'text-ink-muted',
          !quiet && minor > 0 && 'text-receivable',
          !quiet && minor < 0 && 'text-payable',
          !quiet && minor === 0 && 'text-ink-faint',
        )}
      >
        {formatMoney(Math.abs(minor), currency)}
      </p>
      {baseCurrency && baseCurrency !== currency && minor !== 0 ? (
        <p className="tnum text-[0.75rem] text-ink-faint">
          {baseMinor == null
            ? `No ${currency} → ${baseCurrency} rate yet`
            : formatApprox(Math.abs(baseMinor), baseCurrency)}
        </p>
      ) : null}
      <p className="text-[0.75rem] text-ink-faint">{caption}</p>
    </div>
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
