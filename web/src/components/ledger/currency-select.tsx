'use client';

import { useId } from 'react';
import { CURRENCIES } from '@/lib/currencies';
import { cn } from '@/components/ui/primitives';

/**
 * Choosing a currency (upgrade §1, §19).
 *
 * A native `<select>` on purpose. It is the one control every platform already
 * renders as a scrollable, type-ahead, keyboard-navigable list of 46 items, and
 * a hand-built combobox would be worse at all three on the device where this
 * gets used most.
 *
 * Every option shows the ISO code first and the name after it, because `$` is
 * four different currencies and the code is the only unambiguous part.
 */
export function CurrencySelect({
  name,
  value,
  onChange,
  label = 'Currency',
  hint,
  error,
  disabled = false,
  className,
}: {
  name: string;
  value: string;
  onChange?: (next: string) => void;
  label?: string;
  hint?: string;
  error?: string;
  disabled?: boolean;
  className?: string;
}) {
  const id = useId();

  return (
    <div className={cn('space-y-1.5', className)}>
      <div className="flex items-baseline justify-between gap-2">
        <label htmlFor={id} className="text-[0.8125rem] font-medium text-ink">
          {label}
        </label>
        {hint ? <span className="text-[0.75rem] text-ink-faint">{hint}</span> : null}
      </div>

      <select
        id={id}
        name={name}
        value={value}
        disabled={disabled}
        aria-invalid={Boolean(error)}
        onChange={(event) => onChange?.(event.target.value)}
        className={cn(
          'h-11 w-full rounded-lg border bg-surface px-3 text-sm text-ink',
          'transition-[border-color,box-shadow] duration-[var(--dur)] ease-[var(--ease)]',
          'focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/25',
          'disabled:cursor-not-allowed disabled:opacity-60',
          error ? 'border-payable ring-2 ring-payable/20' : 'border-line-strong',
        )}
      >
        {CURRENCIES.map((currency) => (
          <option key={currency.code} value={currency.code}>
            {currency.code} — {currency.name} ({currency.symbol})
          </option>
        ))}
      </select>

      {error ? (
        <p className="text-[0.8125rem] text-payable" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  );
}
