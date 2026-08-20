'use client';

import { useCallback, useEffect, useRef, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { CloseIcon } from '@/components/icons';
import { cn } from '@/components/ui/primitives';

/**
 * Modal sheet. Bottom sheet on mobile, centred dialog from `sm` up
 * (context.md §29).
 *
 * Accessibility handled here rather than per-caller: Escape closes, focus moves
 * into the panel on open and returns to the trigger on close, Tab is trapped,
 * and the background is inert to scroll.
 */
export function Modal({
  open,
  onClose,
  title,
  description,
  children,
  size = 'md',
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  children: ReactNode;
  size?: 'md' | 'lg';
}) {
  const panelRef = useRef<HTMLDivElement>(null);
  const restoreFocusTo = useRef<HTMLElement | null>(null);

  const focusables = useCallback(() => {
    const root = panelRef.current;
    if (!root) return [] as HTMLElement[];
    return [
      ...root.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      ),
    ].filter((el) => el.offsetParent !== null || el === document.activeElement);
  }, []);

  useEffect(() => {
    if (!open) return;

    restoreFocusTo.current = document.activeElement as HTMLElement | null;
    const { overflow } = document.body.style;
    document.body.style.overflow = 'hidden';

    // Focus the first real control, not the close button, so the user can type
    // straight away — this modal is mostly "enter an amount".
    const timer = window.setTimeout(() => {
      const items = focusables();
      (items.find((el) => el.dataset.autofocus === 'true') ?? items[0])?.focus();
    }, 20);

    function onKeyDown(event: KeyboardEvent) {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
        return;
      }
      if (event.key !== 'Tab') return;

      const items = focusables();
      if (items.length === 0) return;
      const first = items[0]!;
      const last = items[items.length - 1]!;

      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }

    document.addEventListener('keydown', onKeyDown);
    return () => {
      document.removeEventListener('keydown', onKeyDown);
      document.body.style.overflow = overflow;
      window.clearTimeout(timer);
      restoreFocusTo.current?.focus?.();
    };
  }, [open, onClose, focusables]);

  if (!open || typeof document === 'undefined') return null;

  return createPortal(
    <div className="fixed inset-0 z-50 flex items-end justify-center sm:items-center sm:p-6">
      <div
        className="absolute inset-0 bg-black/55 animate-[fade_var(--dur)_ease-out_both] backdrop-blur-[3px]"
        onClick={onClose}
        aria-hidden
      />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className={cn(
          'relative flex w-full flex-col border border-line bg-raised shadow-[var(--shadow-pop)]',
          // Bottom sheet on touch, centred dialog from `sm` up.
          'rounded-t-panel pb-[env(safe-area-inset-bottom)] sm:rounded-panel sm:pb-0',
          'animate-[sheet-up_var(--dur-slow)_var(--ease)_both] sm:animate-[pop_var(--dur-slow)_var(--ease)_both]',
          size === 'lg' ? 'sm:max-w-2xl' : 'sm:max-w-md',
          'max-h-[92dvh]',
        )}
      >
        {/* Grab handle: the affordance that says this sheet can be dismissed. */}
        <div aria-hidden className="mx-auto mt-2.5 h-1 w-9 rounded-full bg-line-strong sm:hidden" />

        <div className="flex items-start justify-between gap-4 px-5 pt-4 sm:pt-5">
          <div className="min-w-0">
            <h2 className="font-display text-[1.0625rem] font-semibold tracking-tight text-ink">
              {title}
            </h2>
            {description ? (
              <p className="mt-1 text-[0.8125rem] leading-relaxed text-ink-muted">{description}</p>
            ) : null}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="-mr-1 -mt-1 grid size-8 shrink-0 place-items-center rounded-lg text-ink-faint transition-colors duration-[var(--dur)] hover:bg-sunken hover:text-ink"
          >
            <CloseIcon className="size-4" />
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-5 pb-5 pt-4">{children}</div>
      </div>
    </div>,
    document.body,
  );
}

/**
 * Destructive confirmation (context.md §17). Deleting or voiding a financial
 * record is never a single unguarded click.
 */
export function ConfirmDialog({
  open,
  onClose,
  onConfirm,
  title,
  body,
  confirmLabel = 'Confirm',
  pending = false,
  tone = 'danger',
}: {
  open: boolean;
  onClose: () => void;
  onConfirm: () => void;
  title: string;
  body: ReactNode;
  confirmLabel?: string;
  pending?: boolean;
  tone?: 'danger' | 'primary';
}) {
  return (
    <Modal open={open} onClose={onClose} title={title}>
      <div className="space-y-5">
        <div className="text-sm leading-relaxed text-ink-muted">{body}</div>
        <div className="flex justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            disabled={pending}
            className="inline-flex h-10 items-center rounded-field border border-line-strong bg-surface px-4 text-sm font-medium text-ink transition hover:bg-sunken disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={pending}
            data-autofocus="true"
            className={cn(
              'inline-flex h-10 items-center gap-2 rounded-field px-4 text-sm font-medium transition disabled:opacity-50',
              tone === 'danger'
                ? 'bg-payable text-payable-ink hover:brightness-95'
                : 'bg-accent-solid text-accent-ink hover:bg-accent-solid-hover',
            )}
          >
            {pending ? (
              <span className="inline-block size-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
            ) : null}
            {confirmLabel}
          </button>
        </div>
      </div>
    </Modal>
  );
}
