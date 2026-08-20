'use client';

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { createPortal } from 'react-dom';
import { cn } from '@/components/ui/primitives';
import { CheckIcon, CloseIcon } from '@/components/icons';

/**
 * Toasts (context.md §28).
 *
 * Confirmation that does not steal the screen: a settlement lands, the balance
 * on the page has already changed, and this says so in a line the user can
 * ignore. Announced politely rather than assertively so a screen reader
 * finishes the sentence it is on first.
 */

export type ToastTone = 'success' | 'error' | 'info';

interface Toast {
  id: number;
  title: string;
  body?: string;
  tone: ToastTone;
}

interface ToastApi {
  show: (toast: { title: string; body?: string; tone?: ToastTone }) => void;
}

const ToastContext = createContext<ToastApi | null>(null);

export function useToast(): ToastApi {
  const api = useContext(ToastContext);
  // A component that toasts should still work outside the provider (tests,
  // storybook-ish isolation) rather than throwing on render.
  return api ?? { show: () => {} };
}

const LIFETIME = 4200;

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const nextId = useRef(1);
  const [mounted, setMounted] = useState(false);

  useEffect(() => setMounted(true), []);

  const dismiss = useCallback((id: number) => {
    setToasts((current) => current.filter((toast) => toast.id !== id));
  }, []);

  const show = useCallback<ToastApi['show']>(({ title, body, tone = 'info' }) => {
    const id = nextId.current++;
    setToasts((current) => [...current.slice(-2), { id, title, body, tone }]);
    window.setTimeout(() => {
      setToasts((current) => current.filter((toast) => toast.id !== id));
    }, LIFETIME);
  }, []);

  const api = useMemo(() => ({ show }), [show]);

  return (
    <ToastContext.Provider value={api}>
      {children}
      {mounted
        ? createPortal(
            <div
              aria-live="polite"
              aria-atomic="false"
              className="pointer-events-none fixed inset-x-0 bottom-[calc(5.5rem+env(safe-area-inset-bottom))] z-[60] flex flex-col items-center gap-2 px-4 sm:inset-x-auto sm:bottom-6 sm:right-6 sm:items-end sm:px-0"
            >
              {toasts.map((toast) => (
                <ToastCard key={toast.id} toast={toast} onDismiss={() => dismiss(toast.id)} />
              ))}
            </div>,
            document.body,
          )
        : null}
    </ToastContext.Provider>
  );
}

function ToastCard({ toast, onDismiss }: { toast: Toast; onDismiss: () => void }) {
  return (
    <div
      role="status"
      className={cn(
        'pointer-events-auto flex w-full max-w-sm items-start gap-3 rounded-card border bg-raised px-4 py-3',
        'shadow-[var(--shadow-pop)] animate-[pop_var(--dur-slow)_var(--ease)_both]',
        toast.tone === 'success' && 'border-receivable-line',
        toast.tone === 'error' && 'border-payable-line',
        toast.tone === 'info' && 'border-line-strong',
      )}
    >
      <span
        className={cn(
          'mt-0.5 grid size-6 shrink-0 place-items-center rounded-full',
          toast.tone === 'success' && 'bg-receivable-soft text-receivable',
          toast.tone === 'error' && 'bg-payable-soft text-payable',
          toast.tone === 'info' && 'bg-accent-soft text-accent',
        )}
      >
        <CheckIcon className="size-3.5" />
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-[0.8125rem] font-semibold text-ink">{toast.title}</p>
        {toast.body ? (
          <p className="mt-0.5 text-[0.8125rem] leading-snug text-ink-muted">{toast.body}</p>
        ) : null}
      </div>
      <button
        type="button"
        onClick={onDismiss}
        aria-label="Dismiss"
        className="-mr-1 -mt-0.5 grid size-6 shrink-0 place-items-center rounded-md text-ink-faint transition hover:bg-sunken hover:text-ink"
      >
        <CloseIcon className="size-3.5" />
      </button>
    </div>
  );
}

/**
 * The one deliberate flourish in the product: the tick that draws itself when a
 * settlement is recorded. 260ms, once. Reduced motion turns it into a plain
 * tick that is simply there.
 */
export function SettledMark({ className }: { className?: string }) {
  return (
    <span className={cn('relative grid size-14 place-items-center', className)}>
      <span
        aria-hidden
        className="absolute inset-0 rounded-full bg-receivable-soft motion-safe:animate-[ring-out_600ms_var(--ease)_both]"
      />
      <span className="grid size-14 place-items-center rounded-full bg-receivable-soft text-receivable">
        <svg viewBox="0 0 24 24" fill="none" className="size-7" aria-hidden>
          <path
            d="m5 12.5 4.5 4.5L19 7"
            stroke="currentColor"
            strokeWidth="2.25"
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeDasharray="32"
            className="motion-safe:animate-[draw-check_320ms_var(--ease)_both]"
          />
        </svg>
      </span>
    </span>
  );
}
