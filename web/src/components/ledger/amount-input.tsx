'use client';

import { useEffect, useId, useState } from 'react';
import { currencySymbol, parseAmountToMinor, formatMoney, minorToInput } from '@/lib/money';
import { cn } from '@/components/ui/primitives';

const QUICK_SHARES = [0.25, 0.5, 0.75, 1] as const;

/**
 * The amount field (context.md §7, §14).
 *
 * Deliberately a text input, not `type="number"`: number inputs let a wheel
 * scroll silently change a money value, drop leading zeros, and vary in how
 * they handle commas across browsers. Parsing to minor units happens in
 * money.ts, and the value posted is the raw text — the server re-parses it, so
 * the client is never the authority on an amount.
 *
 * It is the largest control in any sheet it appears in, because it is the only
 * one the user really has to think about. When a ceiling is known — settling
 * against an outstanding figure — the quarter steps turn the common cases into
 * one tap without hiding the free-text field they fill in.
 */
export function AmountInput({
  name = 'amount',
  currency = 'INR',
  defaultValue = '',
  autoFocus = false,
  max,
  error,
  onValidChange,
  label = 'Amount',
}: {
  name?: string;
  currency?: string;
  defaultValue?: string;
  autoFocus?: boolean;
  /** Optional ceiling in minor units, e.g. the outstanding amount. */
  max?: number;
  error?: string;
  onValidChange?: (minor: number | null) => void;
  label?: string;
}) {
  const id = useId();
  const [value, setValue] = useState(defaultValue);
  const symbol = currencySymbol(currency);

  // How many decimals are acceptable is a property of the currency being typed
  // in, not a constant: ¥1000 has none and KWD 1.234 has three (upgrade §19).
  const parse = (text: string) => parseAmountToMinor(text, currency);

  // Settling against a different transaction changes the ceiling; a value left
  // over from the previous one would silently be out of range.
  useEffect(() => {
    setValue(defaultValue);
    onValidChange?.(defaultValue.trim() === '' ? null : parseAmountToMinor(defaultValue, currency));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [defaultValue, currency]);

  const minor = value.trim() === '' ? null : parse(value);
  const overMax = minor !== null && max !== undefined && minor > max;
  const localError =
    value.trim() !== '' && minor === null
      ? 'Enter a valid amount'
      : overMax
        ? `That is more than the ${formatMoney(max!, currency)} outstanding`
        : undefined;
  const invalid = Boolean(localError || error);

  function set(next: string) {
    setValue(next);
    onValidChange?.(next.trim() === '' ? null : parse(next));
  }

  return (
    <div className="space-y-2">
      <label htmlFor={id} className="block text-[0.8125rem] font-medium text-ink-muted">
        {label}
      </label>

      <div
        className={cn(
          'flex items-center gap-2 rounded-card border bg-sunken px-4',
          'transition-[border-color,box-shadow,background-color] duration-[var(--dur)] ease-[var(--ease)]',
          invalid
            ? 'border-payable ring-2 ring-payable/20'
            : 'border-line-strong focus-within:border-accent focus-within:bg-surface focus-within:ring-2 focus-within:ring-accent/25',
        )}
      >
        <span className="font-display text-[1.375rem] font-medium text-ink-faint">{symbol}</span>
        <input
          id={id}
          name={name}
          data-autofocus={autoFocus ? 'true' : undefined}
          value={value}
          onChange={(event) => set(event.target.value)}
          inputMode="decimal"
          autoComplete="off"
          placeholder="0"
          aria-invalid={invalid}
          aria-describedby={`${id}-note`}
          className="tnum h-16 w-full bg-transparent font-display text-[1.75rem] font-semibold text-ink outline-none placeholder:text-ink-faint/60"
        />
      </div>

      {max !== undefined && max > 0 ? (
        <div className="flex flex-wrap gap-1.5">
          {QUICK_SHARES.map((share) => {
            const target = share === 1 ? max : Math.round(max * share);
            const active = minor === target && minor !== null;
            return (
              <button
                key={share}
                type="button"
                onClick={() => set(minorToInput(target, currency))}
                aria-pressed={active}
                className={cn(
                  'tap rounded-full border px-3 py-1 text-[0.75rem] font-medium',
                  'transition-[background-color,border-color,color] duration-[var(--dur)] ease-[var(--ease)]',
                  active
                    ? 'border-accent-line bg-accent-soft text-accent'
                    : 'border-line bg-sunken text-ink-muted hover:border-line-strong hover:text-ink',
                )}
              >
                {share === 1 ? 'Full' : `${share * 100}%`}
              </button>
            );
          })}
          <span className="tnum ml-auto self-center text-[0.75rem] text-ink-faint">
            {formatMoney(max, currency)} outstanding
          </span>
        </div>
      ) : null}

      <p id={`${id}-note`} className="min-h-[1.125rem] text-[0.8125rem]">
        {localError || error ? (
          <span className="text-payable" role="alert">
            {localError ?? error}
          </span>
        ) : null}
      </p>
    </div>
  );
}
