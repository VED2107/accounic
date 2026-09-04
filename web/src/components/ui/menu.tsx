'use client';

import {
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import { cn } from '@/components/ui/primitives';

/**
 * A contextual menu (upgrade §47).
 *
 * Built rather than pulled in because the app ships no UI library and this is
 * the last primitive the admin directory needed: a row with four permanently
 * visible buttons is a control panel, not a directory, and the buttons stop
 * being readable as soon as there are more than a handful of rows.
 *
 * The behaviour, not the look, is the reason this is a component:
 *
 *   - It scales from the trigger, not from its own centre. A menu that grows
 *     out of the button that opened it is understood without being read; one
 *     that blooms from the middle of nowhere has to be.
 *   - Escape closes it and returns focus to the trigger, so a keyboard user is
 *     never stranded.
 *   - Arrow keys move between items, Home/End jump the ends, and focus is
 *     trapped in the list while it is open.
 *   - It closes on outside pointerdown, on scroll and on resize, because a menu
 *     anchored to a moving element is worse than no menu.
 *   - It flips above the trigger when there is no room below, and pins itself
 *     inside the viewport horizontally.
 *
 * Motion is one transform and one opacity over 150ms on an ease-out curve —
 * fast enough that a menu opened many times a day never feels like it is being
 * waited on, which is the whole test for a control at this frequency.
 */

export interface MenuItemSpec {
  label: string;
  onSelect: () => void;
  /** Destructive items are tinted and separated from the ordinary ones. */
  destructive?: boolean;
  disabled?: boolean;
  /** A short line under the label, for an action whose effect is not obvious. */
  description?: string;
}

export function Menu({
  label,
  items,
  className,
}: {
  /** Accessible name for the trigger — the row's subject, not just "menu". */
  label: string;
  items: MenuItemSpec[];
  className?: string;
}) {
  const [open, setOpen] = useState(false);
  const [placement, setPlacement] = useState<{ top: number; left: number; above: boolean } | null>(
    null,
  );
  const triggerRef = useRef<HTMLButtonElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const menuId = useId();

  const enabled = items.filter((item) => !item.disabled);

  const close = useCallback(
    (restoreFocus = true) => {
      setOpen(false);
      setPlacement(null);
      if (restoreFocus) triggerRef.current?.focus();
    },
    [],
  );

  // Position against the viewport rather than inside the row, so an overflowing
  // or scroll-clipped ancestor cannot cut the menu in half.
  useLayoutEffect(() => {
    if (!open) return;
    const trigger = triggerRef.current;
    const list = listRef.current;
    if (!trigger || !list) return;

    const box = trigger.getBoundingClientRect();
    const height = list.offsetHeight;
    const width = list.offsetWidth;
    const margin = 8;
    const roomBelow = window.innerHeight - box.bottom;
    const above = roomBelow < height + margin && box.top > height + margin;

    setPlacement({
      top: above ? box.top - height - 6 : box.bottom + 6,
      left: Math.min(Math.max(margin, box.right - width), window.innerWidth - width - margin),
      above,
    });
  }, [open]);

  useEffect(() => {
    if (!open) return;

    const onKey = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.stopPropagation();
        close();
      }
    };
    const onPointerDown = (event: PointerEvent) => {
      const target = event.target as Node;
      if (listRef.current?.contains(target) || triggerRef.current?.contains(target)) return;
      close(false);
    };
    // A menu pinned to viewport coordinates has to go away the moment those
    // coordinates stop meaning anything.
    const onReflow = () => close(false);

    document.addEventListener('keydown', onKey, true);
    document.addEventListener('pointerdown', onPointerDown, true);
    window.addEventListener('scroll', onReflow, true);
    window.addEventListener('resize', onReflow);
    return () => {
      document.removeEventListener('keydown', onKey, true);
      document.removeEventListener('pointerdown', onPointerDown, true);
      window.removeEventListener('scroll', onReflow, true);
      window.removeEventListener('resize', onReflow);
    };
  }, [open, close]);

  // Focus the first item once placed, so the keyboard path works from the
  // first keystroke rather than after a tab.
  useEffect(() => {
    if (!open || !placement) return;
    listRef.current?.querySelector<HTMLButtonElement>('[data-menu-item]')?.focus();
  }, [open, placement]);

  function moveFocus(direction: 1 | -1 | 'first' | 'last') {
    const nodes = Array.from(
      listRef.current?.querySelectorAll<HTMLButtonElement>('[data-menu-item]') ?? [],
    );
    if (nodes.length === 0) return;
    const current = nodes.indexOf(document.activeElement as HTMLButtonElement);
    const next =
      direction === 'first'
        ? 0
        : direction === 'last'
          ? nodes.length - 1
          : (current + direction + nodes.length) % nodes.length;
    nodes[next]?.focus();
  }

  return (
    <>
      <button
        ref={triggerRef}
        type="button"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        aria-label={`Actions for ${label}`}
        onClick={() => (open ? close() : setOpen(true))}
        onKeyDown={(event) => {
          if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
            event.preventDefault();
            setOpen(true);
          }
        }}
        className={cn(
          'tap grid size-9 shrink-0 place-items-center rounded-field border text-ink-faint',
          'transition-[background-color,border-color,color] duration-[var(--dur)] ease-[var(--ease)]',
          'hover:border-line-strong hover:bg-sunken hover:text-ink',
          'active:scale-[0.97] motion-reduce:active:scale-100',
          open ? 'border-line-strong bg-sunken text-ink' : 'border-transparent',
          className,
        )}
      >
        {/* Three dots, drawn rather than typed: a "⋯" character is a glyph from
            whatever font happens to load, at whatever weight it happens to be. */}
        <svg viewBox="0 0 20 20" className="size-4" aria-hidden fill="currentColor">
          <circle cx="4" cy="10" r="1.5" />
          <circle cx="10" cy="10" r="1.5" />
          <circle cx="16" cy="10" r="1.5" />
        </svg>
      </button>

      {open ? (
        <div
          ref={listRef}
          id={menuId}
          role="menu"
          aria-label={`Actions for ${label}`}
          onKeyDown={(event) => {
            if (event.key === 'ArrowDown') {
              event.preventDefault();
              moveFocus(1);
            } else if (event.key === 'ArrowUp') {
              event.preventDefault();
              moveFocus(-1);
            } else if (event.key === 'Home') {
              event.preventDefault();
              moveFocus('first');
            } else if (event.key === 'End') {
              event.preventDefault();
              moveFocus('last');
            } else if (event.key === 'Tab') {
              // Nothing behind the menu is reachable while it is open.
              event.preventDefault();
              moveFocus(event.shiftKey ? -1 : 1);
            }
          }}
          style={{
            top: placement?.top ?? -9999,
            left: placement?.left ?? -9999,
            // Grow from the corner nearest the trigger, so the menu reads as
            // coming out of the button rather than appearing beside it.
            transformOrigin: placement?.above ? 'bottom right' : 'top right',
            visibility: placement ? 'visible' : 'hidden',
          }}
          className={cn(
            'fixed z-50 min-w-52 overflow-hidden rounded-card border border-line-strong bg-raised py-1',
            'shadow-[var(--shadow-pop)]',
            'animate-[pop_var(--dur)_var(--ease)_both]',
          )}
        >
          {items.map((item, index) => {
            const previous = items[index - 1];
            const startsDestructiveGroup = item.destructive && previous && !previous.destructive;
            return (
              <div key={item.label}>
                {startsDestructiveGroup ? (
                  <div aria-hidden className="my-1 h-px bg-line" />
                ) : null}
                <button
                  type="button"
                  role="menuitem"
                  data-menu-item={item.disabled ? undefined : ''}
                  disabled={item.disabled}
                  tabIndex={-1}
                  onClick={() => {
                    close();
                    item.onSelect();
                  }}
                  className={cn(
                    'press flex w-full flex-col items-start gap-0.5 px-3 py-2 text-left text-[0.8125rem]',
                    'transition-colors duration-[var(--dur-fast)] ease-[var(--ease)]',
                    'disabled:cursor-not-allowed disabled:opacity-45',
                    item.destructive
                      ? 'text-payable hover:bg-payable-soft focus-visible:bg-payable-soft'
                      : 'text-ink hover:bg-sunken focus-visible:bg-sunken',
                  )}
                >
                  <span className="font-medium">{item.label}</span>
                  {item.description ? (
                    <span className="text-[0.75rem] leading-snug text-ink-faint">
                      {item.description}
                    </span>
                  ) : null}
                </button>
              </div>
            );
          })}
          {enabled.length === 0 ? (
            <p className="px-3 py-2 text-[0.8125rem] text-ink-faint">Nothing available</p>
          ) : null}
        </div>
      ) : null}
    </>
  );
}
