import type {
  ButtonHTMLAttributes,
  HTMLAttributes,
  InputHTMLAttributes,
  ReactNode,
  SelectHTMLAttributes,
  TextareaHTMLAttributes,
} from 'react';
import { avatarPalette } from '@/lib/avatar-color';

/**
 * Accounic design system primitives (context.md §18, §32).
 *
 * Every screen is built from these. Nothing in the app styles a button, a card,
 * a field or an avatar by hand — one-off styling is what makes an application
 * look assembled rather than designed.
 *
 * All of them are Server Components. None needs interactivity, so none of this
 * reaches the client bundle.
 */

export function cn(...parts: Array<string | false | null | undefined>): string {
  return parts.filter(Boolean).join(' ');
}

/* -------------------------------------------------------------------------- */
/* Button                                                                      */
/* -------------------------------------------------------------------------- */

type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'receivable' | 'payable';
type ButtonSize = 'sm' | 'md' | 'lg';

const BUTTON_BASE =
  'inline-flex items-center justify-center gap-2 rounded-field font-medium select-none whitespace-nowrap ' +
  'transition-[background-color,border-color,color,box-shadow,transform] duration-[var(--dur)] ease-[var(--ease)] ' +
  'disabled:cursor-not-allowed disabled:opacity-50 ' +
  'active:scale-[0.985] motion-reduce:active:scale-100';

const BUTTON_VARIANT: Record<ButtonVariant, string> = {
  // A tonal gradient, not a rainbow one: the field stays dark enough for white
  // text to clear 4.5:1 at both ends.
  primary:
    'bg-accent-solid [background-image:var(--grad-action)] text-accent-ink ' +
    'shadow-[0_1px_0_0_rgb(255_255_255/0.14)_inset,0_6px_16px_-8px_rgb(37_99_235/0.7)] ' +
    'hover:brightness-110',
  secondary: 'bg-surface text-ink border border-line-strong hover:bg-sunken hover:border-ink-faint/40',
  ghost: 'text-ink-muted hover:text-ink hover:bg-sunken',
  danger: 'bg-payable text-payable-ink hover:brightness-95',
  receivable: 'bg-receivable text-receivable-ink hover:brightness-95',
  payable: 'bg-payable text-payable-ink hover:brightness-95',
};

const BUTTON_SIZE: Record<ButtonSize, string> = {
  sm: 'h-8 px-3 text-[0.8125rem]',
  md: 'h-10 px-4 text-sm',
  lg: 'h-12 px-5 text-[0.9375rem]',
};

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  full?: boolean;
}

export function Button({
  variant = 'primary',
  size = 'md',
  full = false,
  className,
  ...props
}: ButtonProps) {
  return (
    <button
      className={cn(
        BUTTON_BASE,
        BUTTON_VARIANT[variant],
        BUTTON_SIZE[size],
        full && 'w-full',
        className,
      )}
      {...props}
    />
  );
}

/** The same styling as Button, for the times the control has to be an anchor. */
export function buttonClass(
  variant: ButtonVariant = 'primary',
  size: ButtonSize = 'md',
  className?: string,
) {
  return cn(BUTTON_BASE, BUTTON_VARIANT[variant], BUTTON_SIZE[size], className);
}

export function Spinner({ className }: { className?: string }) {
  return (
    <span
      aria-hidden
      className={cn(
        'inline-block size-4 shrink-0 animate-spin rounded-full border-2 border-current border-t-transparent',
        className,
      )}
    />
  );
}

/* -------------------------------------------------------------------------- */
/* Form fields                                                                 */
/* -------------------------------------------------------------------------- */

const CONTROL =
  'w-full rounded-field border border-line-strong bg-sunken px-3 text-ink placeholder:text-ink-faint ' +
  'transition-[border-color,box-shadow,background-color] duration-[var(--dur)] ease-[var(--ease)] ' +
  'focus:border-accent focus:bg-surface focus:outline-none focus:ring-2 focus:ring-accent/25 ' +
  'disabled:opacity-60';

export interface FieldProps {
  label: string;
  htmlFor?: string;
  hint?: string;
  error?: string | undefined;
  children: ReactNode;
  className?: string;
}

export function Field({ label, htmlFor, hint, error, children, className }: FieldProps) {
  return (
    <div className={cn('space-y-1.5', className)}>
      <label htmlFor={htmlFor} className="block text-[0.8125rem] font-medium text-ink-muted">
        {label}
      </label>
      {children}
      {error ? (
        <p className="text-[0.8125rem] text-payable" role="alert">
          {error}
        </p>
      ) : hint ? (
        <p className="text-[0.8125rem] text-ink-faint">{hint}</p>
      ) : null}
    </div>
  );
}

export function Input({ className, ...props }: InputHTMLAttributes<HTMLInputElement>) {
  return <input className={cn(CONTROL, 'h-10 text-sm', className)} {...props} />;
}

export function Textarea({ className, ...props }: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea className={cn(CONTROL, 'min-h-20 py-2 text-sm leading-relaxed', className)} {...props} />
  );
}

export function Select({ className, ...props }: SelectHTMLAttributes<HTMLSelectElement>) {
  return <select className={cn(CONTROL, 'h-10 pr-8 text-sm', className)} {...props} />;
}

/* -------------------------------------------------------------------------- */
/* Surfaces                                                                    */
/* -------------------------------------------------------------------------- */

export function Card({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        'rounded-card border border-line bg-surface shadow-[var(--shadow-card)]',
        className,
      )}
      {...props}
    />
  );
}

/**
 * The larger surface a page's hero information sits on. One brand hairline
 * along the top edge — the only place the full gradient appears in the chrome.
 */
export function Panel({ className, ...props }: HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn(
        'brand-rule overflow-hidden rounded-panel border border-line bg-raised shadow-[var(--shadow-raised)]',
        className,
      )}
      {...props}
    />
  );
}

export function CardHeader({
  title,
  action,
  description,
}: {
  title: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-4 border-b border-line px-5 py-3.5">
      <div className="min-w-0">
        <h2 className="font-display text-[0.9375rem] font-semibold tracking-tight text-ink">
          {title}
        </h2>
        {description ? <p className="mt-0.5 text-[0.8125rem] text-ink-muted">{description}</p> : null}
      </div>
      {action}
    </div>
  );
}

/** Consistent page title block. Every screen opens with one. */
export function PageHeader({
  eyebrow,
  title,
  description,
  action,
  className,
}: {
  eyebrow?: ReactNode;
  title: ReactNode;
  description?: ReactNode;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <header className={cn('mb-6 flex flex-wrap items-end justify-between gap-4', className)}>
      <div className="min-w-0">
        {eyebrow ? (
          <p className="text-[0.8125rem] font-medium text-ink-muted">{eyebrow}</p>
        ) : null}
        <h1 className="font-display text-[1.6rem] font-semibold tracking-tight text-ink sm:text-[1.75rem]">
          {title}
        </h1>
        {description ? (
          <p className="mt-1 text-[0.8125rem] text-ink-muted">{description}</p>
        ) : null}
      </div>
      {action ? <div className="shrink-0">{action}</div> : null}
    </header>
  );
}

/* -------------------------------------------------------------------------- */
/* Avatar                                                                      */
/* -------------------------------------------------------------------------- */

type AvatarTone = 'neutral' | 'receivable' | 'payable' | 'accent';

const AVATAR_TONE: Record<AvatarTone, string> = {
  neutral: 'bg-sunken text-ink-muted border-line',
  receivable: 'bg-receivable-soft text-receivable border-receivable-line',
  payable: 'bg-payable-soft text-payable border-payable-line',
  accent: 'bg-accent-soft text-accent border-accent-line',
};

/**
 * Initials avatar.
 *
 * Pass `identity` — the person's name — and the avatar takes a stable colour of
 * its own, so a directory reads as a set of distinct faces rather than a wall of
 * red and green. Red and green then mean money and only money, which is the
 * whole point of reserving them (lib/avatar-color.ts).
 *
 * The `tone` fallback stays for the handful of places where the avatar really is
 * about state rather than identity — a disabled account in the admin list.
 */
export function Avatar({
  children,
  tone = 'neutral',
  size = 'md',
  identity,
  className,
}: {
  children: ReactNode;
  tone?: AvatarTone;
  size?: 'sm' | 'md' | 'lg';
  identity?: string;
  className?: string;
}) {
  const sizes = {
    sm: 'size-8 rounded-[0.625rem] text-[0.6875rem]',
    md: 'size-10 rounded-xl text-[0.8125rem]',
    lg: 'size-14 rounded-2xl text-base',
  };

  const palette = identity ? avatarPalette(identity) : null;

  return (
    <span
      aria-hidden
      style={
        palette
          ? {
              backgroundColor: palette.bg,
              color: palette.fg,
              borderColor: palette.border,
            }
          : undefined
      }
      className={cn(
        'grid shrink-0 place-items-center border font-semibold tracking-tight',
        sizes[size],
        palette ? null : AVATAR_TONE[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}

/* -------------------------------------------------------------------------- */
/* Badges                                                                      */
/* -------------------------------------------------------------------------- */

export function Badge({
  children,
  tone = 'neutral',
  className,
}: {
  children: ReactNode;
  tone?: 'neutral' | 'receivable' | 'payable' | 'accent' | 'muted';
  className?: string;
}) {
  const tones: Record<string, string> = {
    neutral: 'bg-sunken text-ink-muted border-line',
    muted: 'bg-transparent text-ink-faint border-line',
    receivable: 'bg-receivable-soft text-receivable border-receivable-line',
    payable: 'bg-payable-soft text-payable border-payable-line',
    accent: 'bg-accent-soft text-accent border-accent-line',
  };
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[0.6875rem] font-medium',
        tones[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}

/* -------------------------------------------------------------------------- */
/* Tabs / segmented control                                                    */
/* -------------------------------------------------------------------------- */

/** The container. Works for links (server) and buttons (client) alike. */
export const SEGMENT_GROUP =
  'inline-flex items-center gap-0.5 rounded-field border border-line bg-sunken p-0.5';

export function segmentClass(active: boolean) {
  return cn(
    'rounded-[0.5rem] px-3 py-1.5 text-center text-[0.8125rem] font-medium',
    'transition-[background-color,color,box-shadow] duration-[var(--dur)] ease-[var(--ease)]',
    active
      ? 'bg-surface text-ink shadow-[var(--shadow-card)]'
      : 'text-ink-muted hover:text-ink',
  );
}

/* -------------------------------------------------------------------------- */
/* Loading + empty (context.md §27, §28)                                       */
/* -------------------------------------------------------------------------- */

export function Skeleton({ className }: { className?: string }) {
  return <div aria-hidden className={cn('skeleton', className)} />;
}

export function EmptyState({
  title,
  description,
  action,
  icon,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
  icon?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-14 text-center">
      {icon ? (
        <div className="mb-4 grid size-12 place-items-center rounded-2xl border border-line bg-sunken text-ink-faint">
          {icon}
        </div>
      ) : null}
      <p className="font-display text-[0.9375rem] font-semibold text-ink">{title}</p>
      {description ? (
        <p className="mt-1.5 max-w-xs text-[0.8125rem] leading-relaxed text-ink-muted">
          {description}
        </p>
      ) : null}
      {action ? <div className="mt-5">{action}</div> : null}
    </div>
  );
}

export function ErrorNote({ children }: { children: ReactNode }) {
  return (
    <p
      role="alert"
      className="rounded-field border border-payable-line bg-payable-soft px-3 py-2 text-[0.8125rem] text-payable"
    >
      {children}
    </p>
  );
}

export function SuccessNote({ children }: { children: ReactNode }) {
  return (
    <p
      role="status"
      className="rounded-field border border-receivable-line bg-receivable-soft px-3 py-2 text-[0.8125rem] text-receivable"
    >
      {children}
    </p>
  );
}

/* -------------------------------------------------------------------------- */
/* Form sections                                                               */
/* -------------------------------------------------------------------------- */

/**
 * A group of related fields under one heading (upgrade §1).
 *
 * A form of nine controls where every control looks the same is nine decisions
 * presented at once. Grouped — identity, currency, opening balance, contact —
 * it is four, and each one can be read and dismissed before the next.
 *
 * The heading is a hairline label, not a card. Boxing every group would put six
 * borders on one form and make the sheet read as a settings page; the rule
 * above each group does the same separating job with a single pixel.
 */
export function FormSection({
  title,
  description,
  aside,
  children,
  className,
}: {
  title: string;
  description?: ReactNode;
  /** Right-aligned note beside the heading — a hint, a count, a link. */
  aside?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section
      className={cn(
        // The rule belongs to the section, not to the gap, so the first one in a
        // form drops it without the parent having to know which child is first.
        'border-t border-line pt-5 first:border-t-0 first:pt-0',
        className,
      )}
    >
      <div className="mb-3 flex items-baseline justify-between gap-3">
        <div className="min-w-0">
          <h3 className="stat-label">{title}</h3>
          {description ? (
            <p className="mt-1 text-[0.8125rem] leading-relaxed text-ink-muted">{description}</p>
          ) : null}
        </div>
        {aside ? <div className="shrink-0 text-[0.75rem] text-ink-faint">{aside}</div> : null}
      </div>
      <div className="space-y-4">{children}</div>
    </section>
  );
}

/** The container every sectioned form uses, so the rhythm is identical. */
export function FormSections({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return <div className={cn('space-y-5', className)}>{children}</div>;
}

/**
 * A quiet explanatory block inside a form — what a choice will do, what a
 * refusal means. Not an error and not a card: one tone below the field it
 * qualifies.
 */
export function FormNote({
  title,
  children,
  tone = 'neutral',
}: {
  title?: ReactNode;
  children: ReactNode;
  tone?: 'neutral' | 'accent';
}) {
  return (
    <div
      className={cn(
        'rounded-field border px-3.5 py-3 text-[0.8125rem] leading-relaxed',
        tone === 'accent'
          ? 'border-accent-line bg-accent-soft text-ink-muted'
          : 'border-line bg-sunken text-ink-muted',
      )}
    >
      {title ? <p className="font-medium text-ink">{title}</p> : null}
      {children}
    </div>
  );
}
