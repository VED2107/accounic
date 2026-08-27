'use client';

import { useEffect, useId, useState, type ReactNode } from 'react';
import {
  convertMinor,
  normaliseCode,
  parseRateToE9,
  rateSentence,
  rateToInput,
} from '@/lib/currencies';
import { formatApprox, formatMoney, minorToInput, parseAmountToMinor } from '@/lib/money';
import { rateIsManual } from '@/lib/conversion';
import { lookupRate, type RateQuote } from '@/lib/actions';
import { cn } from '@/components/ui/primitives';

/**
 * Live conversion for a cross-currency entry (upgrade §5, §11, §40).
 *
 * The rule this is built around: never hide what was actually exchanged. Both
 * figures are always on screen, the rate that links them is spelled out under
 * them, and where that rate came from — live, cached, or cached and stale — is
 * said in words rather than implied by an icon.
 *
 * Since v1.1.2 there are *two* things "what was actually exchanged" can mean.
 * The rate says Rs 1,000 is AED 44.20; the exchange counter handed over AED 43.
 * Both are true, and the panel below lets the user say which one the ledger
 * should take without ever discarding the other. The default stays automatic —
 * nobody should have to fight the conversion to record an ordinary entry.
 */

export interface ConversionState {
  rate: RateQuote | null;
  loading: boolean;
  /** Set when there is no rate at all and none can be fetched. */
  unavailable: boolean;
}

/**
 * Fetch and hold the rate for one pair, refetching when either side changes.
 *
 * Returns immediately with `rate: null` for a same-currency entry, which is the
 * overwhelmingly common case and must not cost a round trip.
 */
export function useRate(from: string, to: string): ConversionState {
  const [state, setState] = useState<ConversionState>({
    rate: null,
    loading: false,
    unavailable: false,
  });

  useEffect(() => {
    const source = normaliseCode(from);
    const target = normaliseCode(to);

    if (!source || !target || source === target) {
      setState({ rate: null, loading: false, unavailable: false });
      return;
    }

    let cancelled = false;
    setState({ rate: null, loading: true, unavailable: false });

    lookupRate(source, target).then((result) => {
      if (cancelled) return;
      const rate = result.ok ? result.data : null;
      setState({ rate, loading: false, unavailable: rate === null });
    });

    return () => {
      cancelled = true;
    };
  }, [from, to]);

  return state;
}

/** The form field names this panel posts under. */
interface FieldNames {
  entryCurrency: string;
  accountCurrency: string;
  rateE9: string;
  rateSource: string;
  rateMode: string;
  manualRate: string;
  convertedAmount: string;
  conversionMode: string;
}

function fieldNames(prefix: string): FieldNames {
  return prefix === 'opening_'
    ? {
        // The person form already posts the two currencies from its own
        // selects, so those two are suppressed there rather than duplicated.
        entryCurrency: '',
        accountCurrency: '',
        rateE9: 'opening_rate_e9',
        rateSource: 'opening_rate_source',
        rateMode: 'opening_rate_mode',
        manualRate: 'opening_manual_rate',
        convertedAmount: 'opening_converted_amount',
        conversionMode: 'opening_conversion_mode',
      }
    : {
        entryCurrency: 'entry_currency',
        accountCurrency: 'account_currency',
        rateE9: 'rate_e9',
        rateSource: 'rate_source',
        rateMode: 'rate_mode',
        manualRate: 'manual_rate',
        convertedAmount: 'converted_amount',
        conversionMode: 'conversion_mode',
      };
}

/**
 * The whole cross-currency block: the converted figure, where it came from, the
 * option to replace it with what actually changed hands, and the hidden fields
 * that carry all of it to the server.
 *
 * Preview only. The database recomputes the automatic figure from the same
 * amount and the same rate, so a client can never write a number it worked out
 * on its own (context.md §7). The *manual* figure is different in kind: it is
 * not derived from anything, it is what the user says happened, so it does
 * travel — and the automatic one travels beside it as the audit reference.
 */
export function ConversionPanel({
  amountMinor,
  from,
  to,
  state,
  prefix = '',
  defaultMode = 'automatic',
  defaultConvertedMinor = null,
  defaultRateE9 = null,
  defaultRateIsManual = false,
  className,
}: {
  amountMinor: number | null;
  from: string;
  to: string;
  state: ConversionState;
  /** `'opening_'` for the person form's opening balance. */
  prefix?: '' | 'opening_';
  /** Reopening an entry that was already overridden starts on its own figure. */
  defaultMode?: 'automatic' | 'manual';
  defaultConvertedMinor?: number | null;
  /** The rate the entry was stored at, when one is being edited. */
  defaultRateE9?: number | null;
  /** Whether that stored rate was typed by a human (upgrade §45). */
  defaultRateIsManual?: boolean;
  className?: string;
}) {
  const source = normaliseCode(from);
  const target = normaliseCode(to);
  const names = fieldNames(prefix);
  const id = useId();

  const [manual, setManual] = useState(defaultMode === 'manual');
  const [text, setText] = useState(
    defaultConvertedMinor === null ? '' : minorToInput(defaultConvertedMinor, target),
  );

  // The rate override is a separate decision from the amount override, and the
  // two compose: "at 96.50 — and what actually changed hands was 3,850".
  const [rateManual, setRateManual] = useState(defaultRateIsManual);
  const [rateText, setRateText] = useState(
    defaultRateIsManual && defaultRateE9 ? rateToInput(defaultRateE9) : '',
  );

  // Changing the pair, or reopening the sheet on a different entry, resets both
  // overrides: an actual amount and a negotiated rate belong to one exchange
  // and mean nothing on the next one.
  useEffect(() => {
    setManual(defaultMode === 'manual');
    setText(defaultConvertedMinor === null ? '' : minorToInput(defaultConvertedMinor, target));
    setRateManual(defaultRateIsManual);
    setRateText(defaultRateIsManual && defaultRateE9 ? rateToInput(defaultRateE9) : '');
  }, [defaultMode, defaultConvertedMinor, defaultRateE9, defaultRateIsManual, target, source]);

  if (!source || !target || source === target) return null;

  if (state.loading) {
    return (
      <div
        className={cn(
          'rounded-card border border-line bg-sunken px-4 py-3.5',
          className,
        )}
      >
        <p className="stat-label">Converted amount</p>
        <div className="mt-2 flex items-center gap-2.5">
          <span aria-hidden className="skeleton h-6 w-32 rounded-md" />
        </div>
        <p className="mt-2 text-[0.8125rem] text-ink-muted" role="status">
          Fetching today’s {source} → {target} rate…
        </p>
      </div>
    );
  }

  if (state.unavailable || !state.rate) {
    return (
      <div
        role="alert"
        className={cn(
          'rounded-card border border-payable-line bg-payable-soft px-4 py-3.5',
          className,
        )}
      >
        <p className="text-[0.875rem] font-semibold text-payable">
          Couldn’t get a {source} → {target} rate
        </p>
        <p className="mt-1 text-[0.8125rem] leading-relaxed text-ink-muted">
          None is cached on this account either. Nothing you have entered is lost — enter the
          amount in {target} instead, and put the {source} figure in the note.
        </p>
      </div>
    );
  }

  // The rate this entry will actually be written at. A rate the user typed is
  // used at its full stored precision, exactly as the database will use it.
  // Nothing here ever converts at the shortened rate the sentence prints.
  const fetchedRateE9 = state.rate.rate_e9;
  const typedRate = rateText.trim();
  const typedRateE9 = rateManual && typedRate !== '' ? parseRateToE9(typedRate) : null;
  const rateInvalid = rateManual && typedRate !== '' && typedRateE9 === null;
  const rateE9 = typedRateE9 ?? fetchedRateE9;

  const automatic = amountMinor === null ? null : convertMinor(amountMinor, source, target, rateE9);

  const typed = text.trim();
  const manualMinor = typed === '' ? null : parseAmountToMinor(typed, target);
  const manualInvalid = manual && typed !== '' && manualMinor === null;

  return (
    <div className={cn('overflow-hidden rounded-card border border-line bg-sunken', className)}>
      {/* What was entered. Never hidden, never restated as the converted figure:
          it is the only number the user actually typed (upgrade §2). */}
      <ConversionRow
        label="Original amount"
        value={amountMinor === null ? '—' : formatMoney(amountMinor, source, { withCode: false })}
        unit={source}
        muted
      />

      <ConversionRow
        label="Converted amount"
        value={automatic === null ? '—' : `≈ ${formatMoney(automatic, target, { withCode: false, compactDecimals: false })}`}
        unit={target}
        // The provenance sits with the figure it qualifies rather than at the
        // foot of the panel, so "where did this number come from" is answered
        // on the same line the number is read. The rate is printed at whatever
        // precision reproduces the figure above it (lib/currencies.ts).
        meta={
          <>
            <span className={cn('font-medium', rateManual ? 'text-accent' : 'text-ink-muted')}>
              {rateManual ? 'Custom rate' : 'Automatic'}
            </span>
            <span aria-hidden className="text-ink-subtle"> · </span>
            {rateSentence(source, target, rateE9, amountMinor)}
            {rateManual ? null : (
              <>
                <span aria-hidden className="text-ink-subtle"> · </span>
                <span className={state.rate.stale ? 'font-medium text-payable' : undefined}>
                  {state.rate.provenance}
                </span>
              </>
            )}
          </>
        }
        dimmed={manual}
      />

      {rateManual ? (
        <div className="border-t border-line px-4 py-3.5">
          <div className="flex items-baseline justify-between gap-3">
            <label htmlFor={`${id}-rate`} className="text-[0.8125rem] font-medium text-ink">
              Exchange rate
            </label>
            <span className="text-[0.6875rem] font-medium uppercase tracking-[0.07em] text-accent">
              Manual
            </span>
          </div>

          <div
            className={cn(
              'mt-2 flex items-center gap-2 rounded-field border bg-surface px-3',
              'transition-[border-color,box-shadow] duration-[var(--dur)] ease-[var(--ease)]',
              rateInvalid
                ? 'border-payable ring-2 ring-payable/20'
                : 'border-line-strong focus-within:border-accent focus-within:ring-2 focus-within:ring-accent/25',
            )}
          >
            <span className="shrink-0 text-[0.8125rem] font-medium text-ink-faint">
              1 {source} =
            </span>
            <input
              id={`${id}-rate`}
              value={rateText}
              onChange={(event) => setRateText(event.target.value)}
              inputMode="decimal"
              autoComplete="off"
              placeholder={rateToInput(fetchedRateE9)}
              aria-label={`Rate: one ${source} in ${target}`}
              aria-invalid={rateInvalid}
              aria-describedby={`${id}-rate-note`}
              className="money tnum h-11 w-full bg-transparent text-[1.0625rem] text-ink outline-none placeholder:text-ink-subtle"
            />
            <span className="shrink-0 text-[0.8125rem] font-medium text-ink-faint">{target}</span>
          </div>

          <p id={`${id}-rate-note`} className="mt-2 text-[0.8125rem] leading-relaxed">
            {rateInvalid ? (
              <span className="text-payable" role="alert">
                Enter how many {target} one {source} is worth, to at most nine decimals.
              </span>
            ) : (
              <span className="text-ink-muted">
                Frozen on this entry. Later rate changes will not touch it.
              </span>
            )}
          </p>
        </div>
      ) : null}

      {manual ? (
        <div className="border-t border-line px-4 py-3.5">
          <div className="flex items-baseline justify-between gap-3">
            <label htmlFor={id} className="text-[0.8125rem] font-medium text-ink">
              Actual amount
            </label>
            <span className="text-[0.6875rem] font-medium uppercase tracking-[0.07em] text-accent">
              Manual
            </span>
          </div>

          <div
            className={cn(
              'mt-2 flex items-center gap-2 rounded-field border bg-surface px-3',
              'transition-[border-color,box-shadow] duration-[var(--dur)] ease-[var(--ease)]',
              manualInvalid
                ? 'border-payable ring-2 ring-payable/20'
                : 'border-line-strong focus-within:border-accent focus-within:ring-2 focus-within:ring-accent/25',
            )}
          >
            <span className="text-[0.8125rem] font-medium text-ink-faint">{target}</span>
            <input
              id={id}
              value={text}
              onChange={(event) => setText(event.target.value)}
              inputMode="decimal"
              autoComplete="off"
              placeholder={automatic === null ? '0' : minorToInput(automatic, target)}
              aria-label={`Actual amount in ${target}`}
              aria-invalid={manualInvalid}
              aria-describedby={`${id}-note`}
              className="money tnum h-11 w-full bg-transparent text-[1.0625rem] text-ink outline-none placeholder:text-ink-subtle"
            />
          </div>

          <p id={`${id}-note`} className="mt-2 text-[0.8125rem] leading-relaxed">
            {manualInvalid ? (
              <span className="text-payable" role="alert">
                Enter a valid amount in {target}.
              </span>
            ) : (
              <span className="text-ink-muted">
                Recorded instead of the automatic estimate. The {source} amount you entered and
                the rate above are both kept with the entry.
              </span>
            )}
          </p>
        </div>
      ) : null}

      <div className="flex flex-wrap gap-2 border-t border-line px-4 py-2.5">
        <PanelToggle
          active={rateManual}
          onClick={() => {
            // Turning the override on pre-fills the fetched rate, so the user
            // corrects a number rather than facing an empty box.
            if (!rateManual && typedRate === '') setRateText(rateToInput(fetchedRateE9));
            setRateManual(!rateManual);
          }}
        >
          {rateManual ? 'Use today’s rate' : 'Enter a different rate'}
        </PanelToggle>

        <PanelToggle
          active={manual}
          onClick={() => {
            // The common case is "nearly that, but 43", so the box opens on the
            // automatic figure rather than empty.
            if (!manual && typed === '' && automatic !== null) {
              setText(minorToInput(automatic, target));
            }
            setManual(!manual);
          }}
        >
          {manual ? 'Use the automatic conversion' : 'Enter what actually changed hands'}
        </PanelToggle>
      </div>

      <input type="hidden" name={names.conversionMode} value={manual ? 'manual' : 'automatic'} />
      <input type="hidden" name={names.convertedAmount} value={manual ? typed : ''} />
      {/* The rate travels as text and is parsed on the server against the same
          nine-decimal scale the column stores — the client never sends a
          converted figure it worked out from it. The mode is stated rather than
          inferred, so switching back to today's rate is something the form can
          say rather than merely something it forgot to send. */}
      <input type="hidden" name={names.rateMode} value={rateManual ? 'manual' : 'automatic'} />
      <input type="hidden" name={names.manualRate} value={rateManual ? typedRate : ''} />
    </div>
  );
}

/** One of the two override toggles at the foot of the panel. */
function PanelToggle({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-pressed={active}
      className={cn(
        'tap rounded-full border px-3 py-1.5 text-[0.75rem] font-medium',
        'transition-[background-color,border-color,color] duration-[var(--dur)] ease-[var(--ease)]',
        active
          ? 'border-accent-line bg-accent-soft text-accent'
          : 'border-line-strong bg-surface text-ink-muted hover:border-accent-line hover:text-accent',
      )}
    >
      {children}
    </button>
  );
}

/**
 * One line of the conversion panel: what it is, what it is worth, and — under
 * that — where the figure came from.
 *
 * The label is on the left and the figure right-aligned, so the two rows form a
 * column of amounts that lines up rather than two sentences that have to be
 * read in full.
 */
function ConversionRow({
  label,
  value,
  unit,
  meta,
  muted = false,
  dimmed = false,
}: {
  label: string;
  value: string;
  unit: string;
  meta?: ReactNode;
  /** The entered amount: present for reference, not the figure being decided. */
  muted?: boolean;
  /** Superseded by a manual override — still shown, one step back. */
  dimmed?: boolean;
}) {
  return (
    <div
      className={cn(
        'px-4 py-3.5 not-first:border-t not-first:border-line',
        dimmed && 'opacity-70',
      )}
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-[0.8125rem] font-medium text-ink-muted">{label}</span>
        <span className="flex items-baseline gap-1.5">
          <span className={cn('money tnum text-[1.0625rem]', muted ? 'text-ink-muted' : 'text-ink')}>
            {value}
          </span>
          <span className="text-[0.75rem] font-medium text-ink-faint">{unit}</span>
        </span>
      </div>
      {meta ? <p className="mt-1.5 text-[0.75rem] leading-relaxed text-ink-faint">{meta}</p> : null}
    </div>
  );
}

/**
 * The currency and rate the entry travels with.
 *
 * Rendered unconditionally beside the panel, not inside it: the panel draws
 * nothing for a same-currency entry and nothing while a rate is still being
 * fetched, and in both of those cases the server still has to be told which
 * currency the amount was typed in.
 *
 * The rate travels, the automatic converted amount does not: the database
 * recomputes that from the entered amount and this rate, so a client can never
 * write a derived number it worked out on its own (context.md §7).
 */
export function ConversionFields({
  entryCurrency,
  accountCurrency,
  state,
  prefix = '',
}: {
  entryCurrency: string;
  accountCurrency: string;
  state: ConversionState;
  prefix?: '' | 'opening_';
}) {
  const names = fieldNames(prefix);

  return (
    <>
      {names.entryCurrency ? (
        <input type="hidden" name={names.entryCurrency} value={normaliseCode(entryCurrency)} />
      ) : null}
      {names.accountCurrency ? (
        <input type="hidden" name={names.accountCurrency} value={normaliseCode(accountCurrency)} />
      ) : null}
      <input type="hidden" name={names.rateE9} value={state.rate?.rate_e9 ?? ''} />
      <input type="hidden" name={names.rateSource} value={state.rate?.source ?? ''} />
    </>
  );
}

/**
 * The rate a stored entry was written at — the tertiary line of the hierarchy.
 *
 *     400 AED                    the original amount, printed by the row
 *     ≈ ₹10,393.69 INR           its base equivalent, printed by the row
 *     1 AED = ₹25.984225 INR     this
 *
 * It never repeats either figure. It says what links them, at whatever
 * precision reproduces the converted amount beside it, and then says the two
 * things a reader cannot infer from the numbers: that a human typed the rate,
 * and that a human replaced the converted amount.
 *
 * Used by the person timeline and the activity feed.
 */
export function RateNote({
  enteredMinor,
  enteredCurrency,
  rateE9,
  rateSource,
  accountCurrency,
  conversionMode,
  autoConvertedMinor,
  className,
}: {
  enteredMinor: number | null | undefined;
  enteredCurrency: string | null | undefined;
  rateE9: number | null | undefined;
  rateSource?: string | null;
  accountCurrency: string;
  conversionMode?: string | null;
  autoConvertedMinor?: number | null;
  className?: string;
}) {
  if (!enteredCurrency || !rateE9) return null;

  const manualAmount = conversionMode === 'manual';
  const manualRate = rateIsManual(rateSource);

  return (
    <span className={cn('text-[0.75rem] text-ink-faint', className)}>
      {rateSentence(enteredCurrency, accountCurrency, rateE9, enteredMinor)}
      {manualRate ? (
        <>
          <span aria-hidden className="text-ink-subtle"> · </span>
          <span className="font-medium text-accent">Custom rate</span>
        </>
      ) : null}
      {manualAmount ? (
        <>
          <span aria-hidden className="text-ink-subtle"> · </span>
          <span className="font-medium text-accent">Amount entered by hand</span>
          {autoConvertedMinor
            ? ` (the rate said ${formatMoney(autoConvertedMinor, accountCurrency)})`
            : ''}
        </>
      ) : null}
    </span>
  );
}
