'use client';

import { useEffect, useState } from 'react';
import { convertMinor, normaliseCode, rateSentence } from '@/lib/currencies';
import { formatMinor } from '@/lib/money';
import { lookupRate, type RateQuote } from '@/lib/actions';
import { cn } from '@/components/ui/primitives';

/**
 * Live conversion for a cross-currency entry (upgrade §5, §11).
 *
 * The rule this is built around: never hide what was actually exchanged. Both
 * figures are always on screen, the rate that links them is spelled out under
 * them, and where that rate came from — live, cached, or cached and stale — is
 * said in words rather than implied by an icon.
 *
 * The converted figure shown here is a preview. What gets stored is computed by
 * the database from the same amount and the same rate, so the number the user
 * approved is the number that lands.
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

export function ConversionNote({
  amountMinor,
  from,
  to,
  state,
  className,
}: {
  amountMinor: number | null;
  from: string;
  to: string;
  state: ConversionState;
  className?: string;
}) {
  const source = normaliseCode(from);
  const target = normaliseCode(to);
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

  const converted =
    amountMinor === null ? null : convertMinor(amountMinor, source, target, state.rate.rate_e9);

  return (
    <div
      className={cn(
        'rounded-lg border border-line bg-sunken px-3.5 py-3 text-[0.8125rem]',
        className,
      )}
    >
      <div className="flex items-baseline justify-between gap-3">
        <span className="text-ink-muted">Recorded as</span>
        <span className="tnum font-display text-[1.0625rem] font-semibold text-ink">
          {converted === null ? '—' : formatMinor(converted, target, { withCode: true })}
        </span>
      </div>

      <p className="mt-1.5 text-ink-faint">
        {rateSentence(source, target, state.rate.rate_e9)}
      </p>
      <p
        className={cn(
          'mt-0.5',
          state.rate.stale ? 'font-medium text-payable' : 'text-ink-faint',
        )}
      >
        {state.rate.provenance}
      </p>
    </div>
  );
}

/**
 * The hidden fields that carry the conversion to the server.
 *
 * The rate travels, the converted amount does not: the database recomputes it
 * from the entered amount and this rate, so a client can never write a number
 * it worked out on its own (context.md §7).
 */
export function ConversionFields({
  entryCurrency,
  accountCurrency,
  state,
}: {
  entryCurrency: string;
  accountCurrency: string;
  state: ConversionState;
}) {
  return (
    <>
      <input type="hidden" name="entry_currency" value={normaliseCode(entryCurrency)} />
      <input type="hidden" name="account_currency" value={normaliseCode(accountCurrency)} />
      <input type="hidden" name="rate_e9" value={state.rate?.rate_e9 ?? ''} />
      <input type="hidden" name="rate_source" value={state.rate?.source ?? ''} />
    </>
  );
}

/**
 * How a stored entry is shown afterwards: what was handed over, and what it was
 * worth in the account's currency. Used by the timeline and the activity feed.
 */
export function ConvertedFrom({
  enteredMinor,
  enteredCurrency,
  rateE9,
  accountCurrency,
  className,
}: {
  enteredMinor: number | null | undefined;
  enteredCurrency: string | null | undefined;
  rateE9: number | null | undefined;
  accountCurrency: string;
  className?: string;
}) {
  if (!enteredMinor || !enteredCurrency) return null;

  return (
    <span className={cn('text-[0.75rem] text-ink-faint', className)}>
      {formatMinor(enteredMinor, enteredCurrency, { withCode: true })}
      {rateE9 ? ` · ${rateSentence(enteredCurrency, accountCurrency, rateE9)}` : ''}
    </span>
  );
}
