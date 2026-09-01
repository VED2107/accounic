'use client';

import { useEffect } from 'react';
import { usePathname } from 'next/navigation';

import { reportError } from '@/lib/telemetry';

/**
 * The two things a browser throws that nothing else catches (Phase 2).
 *
 * React's error boundary — `app/error.tsx` — catches a render that threw. It
 * does not catch:
 *
 *   * an error in an event handler, a timer or a callback (`window.onerror`);
 *   * a rejected promise nobody awaited (`unhandledrejection`), which is what
 *     a failed fetch in a click handler actually is.
 *
 * Both were silent in production. Mounted once in the app shell, this listens
 * for them and reports them the way everything else is reported: sanitised,
 * to the user's own database, with the route they were on.
 *
 * It renders nothing.
 */
export function TelemetryListener() {
  const pathname = usePathname();

  useEffect(() => {
    function onError(event: ErrorEvent) {
      void reportError({
        errorType: event.error?.name ?? 'Error',
        message: event.error?.message ?? event.message,
        route: pathname,
        operation: 'window_error',
      });
    }

    function onRejection(event: PromiseRejectionEvent) {
      const reason = event.reason;
      void reportError({
        errorType: reason?.name ?? 'UnhandledRejection',
        message: reason?.message ?? String(reason),
        route: pathname,
        operation: 'unhandled_rejection',
      });
    }

    window.addEventListener('error', onError);
    window.addEventListener('unhandledrejection', onRejection);
    return () => {
      window.removeEventListener('error', onError);
      window.removeEventListener('unhandledrejection', onRejection);
    };
  }, [pathname]);

  return null;
}
