import type { CSSProperties, ReactNode } from 'react';
import { cn } from '@/components/ui/primitives';

/**
 * The motion language, part one: entrances (context.md §18).
 *
 * Deliberately CSS, not JavaScript. An entrance is a one-shot, non-interactive
 * animation, so it needs no runtime, no hydration and no client component —
 * which means a list of two hundred ledger rows can stagger without shipping a
 * single byte of animation code to the browser.
 *
 * `prefers-reduced-motion` is handled once, globally, in globals.css.
 */
export function Reveal({
  children,
  delay = 0,
  className,
  as: Tag = 'div',
}: {
  children: ReactNode;
  /** Milliseconds. Keep the whole sequence under ~200ms. */
  delay?: number;
  className?: string;
  as?: 'div' | 'section' | 'li' | 'header';
}) {
  const style = { '--reveal-delay': `${delay}ms` } as CSSProperties;
  return (
    <Tag className={cn('reveal', className)} style={style}>
      {children}
    </Tag>
  );
}

/**
 * Stagger for list rows. Capped at `max` so the tail of a long list is not
 * still fading in a second after the page settled — past about the tenth row
 * the delay stops reading as sequence and starts reading as lag.
 */
export function staggerStyle(index: number, step = 22, max = 10): CSSProperties {
  return { '--reveal-delay': `${Math.min(index, max) * step}ms` } as CSSProperties;
}
