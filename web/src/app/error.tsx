'use client';

import { useEffect } from 'react';
import { Button } from '@/components/ui/primitives';
import { reportError } from '@/lib/telemetry';

/**
 * Last-resort boundary (context.md §26; upgrade §10).
 *
 * Three things a user needs and "Something went wrong" gives none of: what
 * failed, whether their data survived it, and what they can do now. The
 * database's own words are still never rendered — the digest is the handle an
 * administrator can look the incident up by.
 */
export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  useEffect(() => {
    console.error(error);
    // A console in a browser nobody is watching is not a report (Phase 2).
    void reportError({
      errorType: error.name || 'Error',
      message: error.message,
      route: typeof window === 'undefined' ? null : window.location.pathname,
      operation: 'render',
      context: { action: error.digest ?? 'no-digest' },
    });
  }, [error]);

  return (
    <div className="grid min-h-dvh place-items-center px-6">
      <div className="w-full max-w-sm">
        <h1 className="font-display text-[1.125rem] font-semibold tracking-tight text-ink">
          This page couldn’t load
        </h1>
        <p className="mt-2 text-[0.8125rem] leading-relaxed text-ink-muted">
          Something failed on the way to the screen. Try again — this is often a connection
          that dropped.
        </p>
        <p className="mt-1.5 text-[0.8125rem] leading-relaxed text-ink-faint">
          Your people, transactions and balances are safe. Nothing was written.
        </p>

        <Button className="mt-6" onClick={reset}>
          Try again
        </Button>

        {error.digest ? (
          <p className="mt-4 text-[0.75rem] text-ink-subtle">
            If it keeps happening, tell your administrator and mention code {error.digest}.
          </p>
        ) : (
          <p className="mt-4 text-[0.75rem] text-ink-subtle">
            If it keeps happening, tell your administrator.
          </p>
        )}
      </div>
    </div>
  );
}
