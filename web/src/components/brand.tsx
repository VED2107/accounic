import { cn } from '@/components/ui/primitives';

/**
 * The Accounic mark, inline (brand/accounic-icon.svg is the source of truth).
 *
 * Inline rather than an <img> because it appears in the sidebar, the mobile
 * header, the login screen and the empty states — four requests for a 2KB file,
 * and none of them can be tinted or animated once it is an image. The gradient
 * ids are suffixed so several marks on one page cannot collide.
 */
export function AccounicMark({
  className,
  id = 'mark',
}: {
  className?: string;
  /** Unique per instance when more than one mark renders on a page. */
  id?: string;
}) {
  const g = `acc-${id}`;
  return (
    <svg
      viewBox="0 0 512 512"
      role="img"
      aria-label="Accounic"
      className={cn('size-6', className)}
    >
      <defs>
        <linearGradient id={`${g}-a`} x1="0.08" y1="0.02" x2="0.94" y2="0.98">
          <stop offset="0" stopColor="#1D4ED8" />
          <stop offset="0.22" stopColor="#2563EB" />
          <stop offset="0.45" stopColor="#0EA5E9" />
          <stop offset="0.58" stopColor="#06B6D4" />
          <stop offset="0.78" stopColor="#14B8A6" />
          <stop offset="1" stopColor="#22C55E" />
        </linearGradient>
      </defs>
      <path
        d="M96 414 L256 104 L416 414"
        fill="none"
        stroke={`url(#${g}-a)`}
        strokeWidth="58"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <rect x="178" y="362" width="36" height="52" rx="9" fill="#2563EB" />
      <rect x="228" y="322" width="36" height="92" rx="9" fill="#06B6D4" />
      <rect x="278" y="278" width="36" height="136" rx="9" fill="#22C55E" />
    </svg>
  );
}

/**
 * Mark plus wordmark. "Accoun" in ink, "ic" in the gradient — the lock-up from
 * brand/accounic-horizontal.svg, rebuilt in live text so it inherits the theme
 * and stays crisp at any size.
 */
export function AccounicLogo({
  className,
  markClassName,
  id,
}: {
  className?: string;
  markClassName?: string;
  id?: string;
}) {
  return (
    <span className={cn('flex items-center gap-2.5', className)}>
      <AccounicMark id={id} className={cn('size-7', markClassName)} />
      <span className="font-display text-[0.9375rem] font-semibold tracking-[-0.02em] text-ink">
        Accoun<span className="brand-text">ic</span>
      </span>
    </span>
  );
}
