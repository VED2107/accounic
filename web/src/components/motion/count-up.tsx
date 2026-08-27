'use client';

import { useEffect, useRef } from 'react';
import { formatMoney } from '@/lib/money';
import { cn } from '@/components/ui/primitives';

/**
 * The motion language, part two: a figure that moves when it changes.
 *
 * It does **not** animate on first paint. A balance counting up from zero every
 * time a page loads is decoration; a balance visibly travelling from ₹17,000 to
 * ₹13,000 the moment a settlement lands is information — it shows the user the
 * consequence of what they just did, on the number they were looking at.
 *
 * GSAP does the tween. It earns its place here: this is an interruptible tween
 * over a formatted value, and a settlement recorded twice in quick succession
 * has to retarget mid-flight rather than fight a second timer. It is loaded
 * dynamically, so it sits in its own chunk and never touches first paint.
 *
 * The server already rendered the correct figure into this element, so with no
 * JavaScript, or with reduced motion, the number is simply right.
 */
export function CountUp({
  minor,
  currency,
  className,
}: {
  minor: number;
  currency: string;
  className?: string;
}) {
  const ref = useRef<HTMLSpanElement>(null);
  const previous = useRef(minor);

  useEffect(() => {
    const node = ref.current;
    const from = previous.current;
    previous.current = minor;

    if (!node || from === minor) return;
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      node.textContent = formatMoney(minor, currency);
      return;
    }

    let cancelled = false;
    let kill: (() => void) | undefined;

    void import('gsap').then(({ gsap }) => {
      if (cancelled) return;
      const value = { current: from };
      const tween = gsap.to(value, {
        current: minor,
        duration: 0.45,
        ease: 'power2.out',
        overwrite: 'auto',
        onUpdate: () => {
          node.textContent = formatMoney(Math.round(value.current), currency);
        },
        onComplete: () => {
          node.textContent = formatMoney(minor, currency);
        },
      });
      kill = () => tween.kill();
    });

    return () => {
      cancelled = true;
      kill?.();
    };
  }, [minor, currency]);

  return (
    <span ref={ref} className={cn('tnum', className)}>
      {formatMoney(minor, currency)}
    </span>
  );
}
