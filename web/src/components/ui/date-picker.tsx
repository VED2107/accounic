'use client';

import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';

import { cn } from '@/components/ui/primitives';
import { ChevronRightIcon } from '@/components/icons';

/**
 * Picking a date, and picking two (context.md §29).
 *
 * The native `<input type="date">` was here first and it is a perfectly correct
 * control — but it renders the *browser's* calendar: its own typeface, its own
 * accent, its own idea of where a week starts, popped over a product that has
 * spent a release deciding all three. It also renders differently in every
 * browser, so the one control on a form that the user has to aim at was the one
 * control we could not draw.
 *
 * So the grid is ours, and it is one grid: `DateField` picks a day, and
 * `DateRangeField` picks two, both from the same calendar, so a date is chosen
 * the same way everywhere in the product.
 *
 * What it is not is a date library — it does arithmetic on a local `Date` and
 * formats with `Intl`, both of which the browser already ships.
 *
 * `DateField` keeps a hidden input carrying its `name`, so it drops into the
 * existing server-action forms exactly where the native input used to sit and
 * submits the same `YYYY-MM-DD` string.
 *
 * Accessibility is the part a custom calendar usually loses, so it is explicit:
 * the grid is a real `role="grid"`, arrows move by a day, PageUp/PageDown by a
 * month, Home/End to the ends of the week, every cell states its full date, and
 * Escape closes the calendar without closing the dialog around it.
 *
 * Mirrored by `app/lib/ui/widgets/date_picker.dart`.
 */

const WEEKDAYS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

/** `2026-09-04` for a local date, never `toISOString` — that shifts by the offset. */
export function toKey(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

function fromKey(key: string): Date | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(key);
  if (!match) return null;
  const date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
  return Number.isNaN(date.getTime()) ? null : date;
}

const startOfMonth = (date: Date) => new Date(date.getFullYear(), date.getMonth(), 1);
const addDays = (date: Date, days: number) =>
  new Date(date.getFullYear(), date.getMonth(), date.getDate() + days);
const addMonths = (date: Date, months: number) =>
  new Date(date.getFullYear(), date.getMonth() + months, 1);

const MONTH_LABEL = new Intl.DateTimeFormat('en-IN', { month: 'long', year: 'numeric' });
const FULL_LABEL = new Intl.DateTimeFormat('en-IN', {
  weekday: 'long',
  day: 'numeric',
  month: 'long',
  year: 'numeric',
});
const SHORT_LABEL = new Intl.DateTimeFormat('en-IN', {
  day: '2-digit',
  month: 'short',
  year: 'numeric',
});

/** The six weeks a month grid always shows, so the calendar never changes height. */
function weeksOf(month: Date): Date[][] {
  const first = startOfMonth(month);
  // Monday-first, which is what the rest of this product assumes.
  const start = addDays(first, -((first.getDay() + 6) % 7));

  const weeks: Date[][] = [];
  for (let week = 0; week < 6; week += 1) {
    const days: Date[] = [];
    for (let day = 0; day < 7; day += 1) days.push(addDays(start, week * 7 + day));
    weeks.push(days);
  }
  return weeks;
}

/** The shared trigger: a field-shaped button that opens the calendar under it. */
function Trigger({
  open,
  setOpen,
  disabled,
  placeholder,
  label,
  children,
  id,
  buttonRef,
}: {
  open: boolean;
  setOpen: (next: boolean) => void;
  disabled?: boolean;
  placeholder: boolean;
  label: string;
  children?: React.ReactNode;
  id?: string;
  buttonRef?: React.RefObject<HTMLButtonElement | null>;
}) {
  return (
    <>
      <button
        type="button"
        id={id}
        ref={buttonRef}
        disabled={disabled}
        onClick={() => setOpen(!open)}
        aria-haspopup="dialog"
        aria-expanded={open}
        className={cn(
          'tap press flex h-11 w-full items-center justify-between gap-2 rounded-field',
          'border border-line-strong bg-sunken px-3 text-sm text-ink',
          'transition-[border-color,background-color,box-shadow] duration-[var(--dur)] ease-[var(--ease)]',
          'hover:bg-surface focus:border-accent focus:outline-none focus:ring-2 focus:ring-accent/25',
          'disabled:cursor-not-allowed disabled:opacity-60',
          open && 'border-accent bg-surface ring-2 ring-accent/25',
        )}
      >
        <span className={cn('tnum truncate', placeholder && 'text-ink-faint')}>{label}</span>
        <ChevronRightIcon
          aria-hidden
          className={cn(
            'size-4 shrink-0 text-ink-faint transition-transform duration-[var(--dur)]',
            open && 'rotate-90',
          )}
        />
      </button>
      {children}
    </>
  );
}

/* -------------------------------------------------------------------------- */
/* One date                                                                    */
/* -------------------------------------------------------------------------- */

export function DateField({
  id,
  name,
  value,
  defaultValue,
  onChange,
  max,
  min,
  disabled = false,
  required = false,
}: {
  id?: string;
  /** When given, a hidden input carries the value into the surrounding form. */
  name?: string;
  /** Controlled. Omit and pass `defaultValue` to let the field keep its own. */
  value?: string;
  defaultValue?: string;
  onChange?: (next: string) => void;
  /** The last selectable day. Defaults to today: a ledger has no future. */
  max?: string;
  min?: string;
  disabled?: boolean;
  required?: boolean;
}) {
  const [own, setOwn] = useState(defaultValue ?? '');
  const current = value ?? own;
  const [open, setOpen] = useState(false);
  const wrapper = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);

  useClickAway(wrapper, open, () => setOpen(false));

  const parsed = fromKey(current);

  return (
    <div ref={wrapper} className="relative">
      {name ? <input type="hidden" name={name} value={current} required={required} /> : null}
      <Trigger
        id={id}
        open={open}
        setOpen={setOpen}
        disabled={disabled}
        placeholder={!parsed}
        label={parsed ? SHORT_LABEL.format(parsed) : 'Pick a date'}
        buttonRef={trigger}
      >
        {open ? (
          <CalendarPanel
            trigger={trigger}
            anchor={parsed ?? new Date()}
            selected={current}
            maxKey={max ?? toKey(new Date())}
            minKey={min}
            onPick={(key) => {
              if (value === undefined) setOwn(key);
              onChange?.(key);
              setOpen(false);
            }}
          />
        ) : null}
      </Trigger>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* Two dates                                                                   */
/* -------------------------------------------------------------------------- */

export interface DateRangeValue {
  from: string;
  to: string;
}

export function DateRangeField({
  value,
  onChange,
  disabled = false,
  max,
}: {
  value: DateRangeValue;
  onChange: (next: DateRangeValue) => void;
  disabled?: boolean;
  max?: string;
}) {
  const [open, setOpen] = useState(false);
  const wrapper = useRef<HTMLDivElement>(null);
  const trigger = useRef<HTMLButtonElement>(null);

  useClickAway(wrapper, open, () => setOpen(false));

  const summary = useMemo(() => {
    const from = fromKey(value.from);
    const to = fromKey(value.to);
    if (!from && !to) return 'Pick two dates';
    if (from && !to) return `${SHORT_LABEL.format(from)} → …`;
    if (!from && to) return `… → ${SHORT_LABEL.format(to)}`;
    return `${SHORT_LABEL.format(from!)} → ${SHORT_LABEL.format(to!)}`;
  }, [value.from, value.to]);

  return (
    <div ref={wrapper} className="relative">
      <Trigger
        open={open}
        setOpen={setOpen}
        disabled={disabled}
        placeholder={!value.from && !value.to}
        label={summary}
        buttonRef={trigger}
      >
        {open ? (
          <CalendarPanel
            trigger={trigger}
            anchor={fromKey(value.from) ?? fromKey(value.to) ?? new Date()}
            rangeFrom={value.from}
            rangeTo={value.to}
            maxKey={max ?? toKey(new Date())}
            onPick={(key) => {
              // First pick sets the start and clears the end; the second closes
              // the range — and a day before the start restarts from there
              // rather than producing a backwards range nobody meant.
              if (!value.from || value.to || key < value.from) {
                onChange({ from: key, to: '' });
                return;
              }
              onChange({ from: value.from, to: key });
              setOpen(false);
            }}
            onClear={() => onChange({ from: '', to: '' })}
          />
        ) : null}
      </Trigger>
    </div>
  );
}

/* -------------------------------------------------------------------------- */
/* The calendar                                                                */
/* -------------------------------------------------------------------------- */

function useClickAway(
  ref: React.RefObject<HTMLElement | null>,
  active: boolean,
  close: () => void,
) {
  useEffect(() => {
    if (!active) return;

    function onPointerDown(event: MouseEvent) {
      const target = event.target as HTMLElement;
      // The panel is portalled to the body, so it is not inside the field's
      // subtree: a containment test alone would close the calendar on the very
      // click that picks a date.
      if (ref.current?.contains(target)) return;
      if (target.closest?.('[data-accounic-calendar]')) return;
      close();
    }
    function onKeyDown(event: KeyboardEvent) {
      if (event.key !== 'Escape') return;
      // Swallowed here so the calendar closes without also closing the dialog
      // it is sitting in — one Escape, one thing.
      event.stopPropagation();
      event.preventDefault();
      close();
    }

    document.addEventListener('mousedown', onPointerDown);
    document.addEventListener('keydown', onKeyDown, true);
    return () => {
      document.removeEventListener('mousedown', onPointerDown);
      document.removeEventListener('keydown', onKeyDown, true);
    };
  }, [ref, active, close]);
}

/**
 * Where the calendar sits, in viewport coordinates.
 *
 * It is portalled to the body rather than positioned inside the field, because
 * a popover that lives in the flow is at the mercy of every ancestor: the
 * reveal animations on these pages set `transform`, which makes a new stacking
 * context, and a `z-30` panel inside one paints *below* the next section
 * regardless of the number. The bug that produced was a calendar with the page
 * showing through it.
 *
 * Being in the viewport also means it can be honest about space: below the
 * field when there is room, above it when there is not, and never off the
 * right-hand edge.
 */
function usePosition(trigger: React.RefObject<HTMLButtonElement | null>, height: number) {
  const [box, setBox] = useState<{ top: number; left: number; width: number } | null>(null);

  const place = useCallback(() => {
    const el = trigger.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const width = Math.max(rect.width, 280);
    const below = window.innerHeight - rect.bottom;

    setBox({
      top: below < height + 12 && rect.top > height + 12 ? rect.top - height - 6 : rect.bottom + 6,
      left: Math.min(Math.max(8, rect.left), Math.max(8, window.innerWidth - width - 8)),
      width,
    });
  }, [trigger, height]);

  useLayoutEffect(() => {
    place();
    window.addEventListener('resize', place);
    // Capture, so the panel keeps up with any scroller it is inside.
    window.addEventListener('scroll', place, true);
    return () => {
      window.removeEventListener('resize', place);
      window.removeEventListener('scroll', place, true);
    };
  }, [place]);

  return box;
}

function CalendarPanel({
  trigger,
  anchor,
  selected,
  rangeFrom,
  rangeTo,
  maxKey,
  minKey,
  onPick,
  onClear,
}: {
  trigger: React.RefObject<HTMLButtonElement | null>;
  anchor: Date;
  selected?: string;
  rangeFrom?: string;
  rangeTo?: string;
  maxKey: string;
  minKey?: string;
  onPick: (key: string) => void;
  onClear?: () => void;
}) {
  const [month, setMonth] = useState(() => startOfMonth(anchor));
  const [focused, setFocused] = useState(anchor);
  const [hovered, setHovered] = useState<string | null>(null);
  const gridRef = useRef<HTMLDivElement>(null);

  const weeks = useMemo(() => weeksOf(month), [month]);
  const todayKey = toKey(new Date());

  // While one end is chosen, the row under the cursor previews the span it
  // would make. Without it, picking a range is two blind clicks.
  const spanFrom = rangeFrom;
  const spanTo = rangeTo || (rangeFrom && !rangeTo ? hovered : null);

  function blocked(key: string) {
    return key > maxKey || (minKey ? key < minKey : false);
  }

  function move(days: number) {
    const next = addDays(focused, days);
    setFocused(next);
    if (next.getMonth() !== month.getMonth() || next.getFullYear() !== month.getFullYear()) {
      setMonth(startOfMonth(next));
    }
  }

  function onKeyDown(event: React.KeyboardEvent) {
    switch (event.key) {
      case 'ArrowLeft':
        move(-1);
        break;
      case 'ArrowRight':
        move(1);
        break;
      case 'ArrowUp':
        move(-7);
        break;
      case 'ArrowDown':
        move(7);
        break;
      case 'Home':
        move(-((focused.getDay() + 6) % 7));
        break;
      case 'End':
        move(6 - ((focused.getDay() + 6) % 7));
        break;
      case 'PageUp':
        setMonth(addMonths(month, -1));
        setFocused(addMonths(focused, -1));
        break;
      case 'PageDown':
        setMonth(addMonths(month, 1));
        setFocused(addMonths(focused, 1));
        break;
      case 'Enter':
      case ' ':
        if (!blocked(toKey(focused))) onPick(toKey(focused));
        break;
      default:
        return;
    }
    event.preventDefault();
  }

  useEffect(() => {
    gridRef.current?.querySelector<HTMLElement>('[data-focused="true"]')?.focus();
  }, [focused]);

  // The height a six-week grid plus its chrome comes to. Measured rather than
  // guessed would be better; guessed is enough to decide which side to open on,
  // and being wrong only costs a few pixels of overlap.
  const height = onClear ? 372 : 336;
  const box = usePosition(trigger, height);

  if (typeof document === 'undefined') return null;

  return createPortal(
    <div
      role="dialog"
      aria-label="Pick a date"
      data-accounic-calendar=""
      style={box ? { top: box.top, left: box.left, width: box.width } : { visibility: 'hidden' }}
      className={cn(
        'fixed z-[60] rounded-card border border-line',
        'bg-raised p-3 shadow-[var(--shadow-pop)]',
        'animate-[pop_var(--dur)_var(--ease)_both]',
      )}
    >
      <div className="mb-2 flex items-center justify-between gap-2">
        <StepButton label="Previous month" onClick={() => setMonth(addMonths(month, -1))}>
          <ChevronRightIcon aria-hidden className="size-4 rotate-180" />
        </StepButton>
        <p aria-live="polite" className="text-[0.8125rem] font-semibold text-ink">
          {MONTH_LABEL.format(month)}
        </p>
        <StepButton label="Next month" onClick={() => setMonth(addMonths(month, 1))}>
          <ChevronRightIcon aria-hidden className="size-4" />
        </StepButton>
      </div>

      <div
        ref={gridRef}
        role="grid"
        aria-label={MONTH_LABEL.format(month)}
        onKeyDown={onKeyDown}
        onMouseLeave={() => setHovered(null)}
      >
        <div role="row" className="mb-1 grid grid-cols-7">
          {WEEKDAYS.map((day) => (
            <div
              key={day}
              role="columnheader"
              aria-label={day}
              className="py-1 text-center text-[0.625rem] font-semibold uppercase tracking-wider text-ink-faint"
            >
              {day}
            </div>
          ))}
        </div>

        {weeks.map((week) => (
          <div role="row" key={toKey(week[0]!)} className="grid grid-cols-7">
            {week.map((day) => {
              const key = toKey(day);
              const outside = day.getMonth() !== month.getMonth();
              const unavailable = blocked(key);
              const isStart = key === spanFrom;
              const isEnd = Boolean(spanTo) && key === spanTo;
              const single = selected === key;
              const inSpan =
                Boolean(spanFrom) && Boolean(spanTo) && key > spanFrom! && key < spanTo!;
              const chosen = single || isStart || isEnd;

              return (
                <button
                  key={key}
                  type="button"
                  role="gridcell"
                  tabIndex={toKey(focused) === key ? 0 : -1}
                  data-focused={toKey(focused) === key}
                  disabled={unavailable}
                  aria-selected={chosen}
                  aria-label={FULL_LABEL.format(day)}
                  onMouseEnter={() => setHovered(key)}
                  onClick={() => onPick(key)}
                  className={cn(
                    'relative h-8 text-[0.8125rem] tnum',
                    'transition-[background-color,color] duration-[var(--dur-fast)] ease-[var(--ease)]',
                    'focus:outline-none focus-visible:ring-2 focus-visible:ring-accent/40',
                    // The span is a continuous band, so its rounding lives on
                    // the two ends rather than on every cell.
                    inSpan && 'bg-accent-soft text-ink',
                    isStart && !isEnd && 'rounded-l-lg',
                    isEnd && !isStart && 'rounded-r-lg',
                    chosen && 'rounded-lg bg-accent-solid font-semibold text-accent-ink',
                    !chosen && !inSpan && 'rounded-lg hover:bg-sunken',
                    !chosen && outside && 'text-ink-subtle',
                    !chosen && !outside && 'text-ink',
                    unavailable && 'cursor-not-allowed text-ink-subtle hover:bg-transparent',
                  )}
                >
                  {day.getDate()}
                  {key === todayKey && !chosen ? (
                    <span
                      aria-hidden
                      className="absolute inset-x-0 bottom-1 mx-auto size-1 rounded-full bg-accent"
                    />
                  ) : null}
                </button>
              );
            })}
          </div>
        ))}
      </div>

      {onClear ? (
        <div className="mt-2 flex items-center justify-between gap-2 border-t border-line pt-2">
          <p className="text-[0.6875rem] text-ink-faint">
            {rangeFrom && !rangeTo ? 'Now pick the end' : 'Pick the start of the range'}
          </p>
          <button
            type="button"
            onClick={() => {
              onClear();
              setHovered(null);
            }}
            className="tap press rounded-lg px-2 py-1 text-[0.75rem] font-medium text-ink-muted transition-colors duration-[var(--dur-fast)] hover:bg-sunken hover:text-ink"
          >
            Clear
          </button>
        </div>
      ) : null}
    </div>,
    document.body,
  );
}

function StepButton({
  label,
  onClick,
  children,
}: {
  label: string;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      className="tap press grid size-7 place-items-center rounded-lg text-ink-muted transition-colors duration-[var(--dur-fast)] hover:bg-sunken hover:text-ink"
    >
      {children}
    </button>
  );
}
