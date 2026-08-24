'use client';

import { useEffect, useId, useState } from 'react';
import { convertMinor, normaliseCode, rateSentence } from '@/lib/currencies';
import { formatMinor, minorToInput, parseAmountToMinor } from '@/lib/money';
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
        convertedAmount: 'opening_converted_amount',
        conversionMode: 'opening_conversion_mode',
      }
    : {
        entryCurrency: 'entry_currency',
        accountCurrency: 'account_currency',
        rateE9: 'rate_e9',
        rateSource: 'rate_source',
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

  // Changing the pair, or reopening the sheet on a different entry, resets the
  // override: an actual amount belongs to one exchange and means nothing on the
  // next one.
  useEffect(() => {
    setManual(defaultMode === 'manual');
    setText(defaultConvertedMinor === null ? '' : minorToInput(defaultConvertedMinor, target));
  }, [defaultMode, defaultConvertedMinor, target, source]);

  if (!source || !target || source === target) return null;

  if (state.loading) {
    return (
      <p className={cn('text-[0.8125rem] text-ink-faint', className)}>
        Fetching today’s {source} → {target} rate…
      </p>
    );
  }

  if (state.unavailable || !state.rate) {
    return (
      <p
        className={cn(
          'rounded-lg border border-payable/40 bg-payable-soft px-3 py-2 text-[0.8125rem] text-payable',
          className,
        )}
        role="alert"
      >
        No {source} → {target} rate is available, and none is cached on this account.
        Enter the amount in {target} instead — nothing is lost, and you can add the{' '}
        {source} figure to the note.
      </p>
    );
  }

  const automatic =
    amountMinor === null ? null : convertMinor(amountMinor, source, target, state.rate.rate_e9);

  const typed = text.trim();
  const manualMinor = typed === '' ? null : parseAmountToMinor(typed, target);
  const manualInvalid = manual && typed !== '' && manualMinor === null;

  return (
    <div className={cn('rounded-lg border border-line bg-sunken px-3.5 py-3', className)}>
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-[0.8125rem] text-ink-muted">
          {manual ? 'Actual amount' : 'Converted amount'}
        </span>
        {manual ? null : (
          <span className="tnum font-display text-[1.0625rem] font-semibold text-ink">
            {automatic === null ? '—' : formatMinor(automatic, target, { withCode: true })}
          </span>
        )}
      </div>

      {manual ? (
        <div className="mt-2 space-y-2">
          <div
            className={cn(
              'flex items-center gap-2 rounded-field border bg-surface px-3',
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
              className="tnum h-11 w-full bg-transparent font-display text-[1.0625rem] font-semibold text-ink outline-none placeholder:text-ink-faint/60"
            />
          </div>

          <p className="text-[0.75rem] font-medium text-accent">Manual override</p>
          {manualInvalid ? (
            <p className="text-[0.75rem] text-payable" role="alert">
              Enter a valid amount in {target}.
            </p>
          ) : null}
          <p className="text-[0.75rem] text-ink-faint">
            Automatic estimate:{' '}
            {automatic === null ? '—' : formatMinor(automatic, target, { withCode: true })} ·{' '}
            {rateSentence(source, target, state.rate.rate_e9)}
          </p>
        </div>
      ) : (
        <>
          <p className="mt-1.5 text-[0.75rem] font-medium text-ink-muted">Automatic</p>
          <p className="mt-0.5 text-[0.8125rem] text-ink-faint">
            {rateSentence(source, target, state.rate.rate_e9)}
          </p>
          <p
            className={cn(
              'mt-0.5 text-[0.8125rem]',
              state.rate.stale ? 'font-medium text-payable' : 'text-ink-faint',
            )}
          >
            {state.rate.provenance}
          </p>
        </>
      )}

      <button
        type="button"
        onClick={() => {
          // Turning the override on pre-fills the automatic figure, so the user
          // edits a number rather than facing an empty box — the common case is
          // "nearly that, but 43".
          if (!manual && typed === '' && automatic !== null) {
            setText(minorToInput(automatic, target));
          }
          setManual(!manual);
        }}
        className="mt-2.5 rounded-full border border-line-strong bg-surface px-3 py-1 text-[0.75rem] font-medium text-ink-muted transition hover:border-accent-line hover:text-accent"
      >
        {manual ? 'Use the automatic conversion' : 'Use actual amount'}
      </button>

      <input type="hidden" name={names.conversionMode} value={manual ? 'manual' : 'automatic'} />
      <input type="hidden" name={names.convertedAmount} value={manual ? typed : ''} />
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
 * How a stored entry is shown afterwards: what was handed over, what it was
 * worth in the account's currency, and — when the two disagree with the rate —
 * that somebody said so on purpose.
 *
 * Used by the timeline and the activity feed.
 */
export function ConvertedFrom({
  enteredMinor,
  enteredCurrency,
  rateE9,
  accountCurrency,
  conversionMode,
  autoConvertedMinor,
  className,
}: {
  enteredMinor: number | null | undefined;
  enteredCurrency: string | null | undefined;
  rateE9: number | null | undefined;
  accountCurrency: string;
  conversionMode?: string | null;
  autoConvertedMinor?: number | null;
  className?: string;
}) {
  if (!enteredMinor || !enteredCurrency) return null;
  const manual = conversionMode === 'manual';

  return (
    <span className={cn('text-[0.75rem] text-ink-faint', className)}>
      {formatMinor(enteredMinor, enteredCurrency, { withCode: true })}
      {rateE9 ? ` · ${rateSentence(enteredCurrency, accountCurrency, rateE9)}` : ''}
      {manual ? (
        <>
          {' · '}
          <span className="font-medium text-accent">Manually entered</span>
          {autoConvertedMinor
            ? ` (rate said ${formatMinor(autoConvertedMinor, accountCurrency, { withCode: true })})`
            : ''}
        </>
      ) : null}
    </span>
  );
}
