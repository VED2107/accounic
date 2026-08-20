'use client';

import { useEffect } from 'react';

/**
 * Last-resort boundary (context.md §26). Shows something useful and never the
 * database's own words — the message is deliberately not rendered.
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
  }, [error]);

  return (
    <div className="grid min-h-dvh place-items-center px-6">
      <div className="w-full max-w-sm text-center">
        <h1 className="text-lg font-semibold tracking-tight">Something went wrong</h1>
        <p className="mt-1.5 text-sm leading-relaxed text-ink-muted">
          Nothing was saved. Try again, and if it keeps happening tell your administrator
          {error.digest ? ` and mention code ${error.digest}` : ''}.
        </p>
        <button
          type="button"
          onClick={reset}
          className="mt-6 inline-flex h-10 items-center rounded-lg bg-accent px-4 text-sm font-medium text-accent-ink transition hover:bg-accent-hover"
        >
          Try again
        </button>
      </div>
    </div>
  );
}
