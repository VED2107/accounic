import { createClient } from '@/lib/supabase/client';

/**
 * Production error telemetry — web (milestone 1.9.0, Phase 2).
 *
 * Until now, a production failure was invisible: `errors.ts` logs only outside
 * production, so the only report anyone ever got was a user saying "it did
 * nothing". Every bug since v1.0.0 was found that way.
 *
 * WHAT THIS SENDS, AND WHAT IT REFUSES TO.
 *
 * A report answers *where did it fail and what was the user doing* — route,
 * operation, error type, a sanitised message, the build, the platform. It must
 * never answer *what are this user's financial records*, so:
 *
 *   * `sanitiseMessage()` strips anything money-shaped, any email address, any
 *     long digit run and any UUID before the message leaves the browser;
 *   * `context` is a fixed set of keys, and only scalars;
 *   * the RPC redacts and whitelists again on arrival (db/migrations/0028),
 *     because a client is a thing that can be wrong.
 *
 * Reports go to the user's own database, not to a third party. The one call
 * site for that is `send()` below: pointing it at Sentry later is a change to
 * this function and nothing else.
 *
 * Mirrored by `app/lib/core/telemetry.dart`.
 */

/** The keys the server keeps. Anything else is dropped there; drop it here too. */
const CONTEXT_KEYS = [
  'screen',
  'action',
  'status_code',
  'sqlstate',
  'attempt',
  'is_offline',
  'locale',
  'theme',
  'device_class',
  'os_version',
  'duration_ms',
  'entry_count',
] as const;

export type TelemetryContext = Partial<
  Record<(typeof CONTEXT_KEYS)[number], string | number | boolean | null>
>;

export interface ErrorReport {
  errorType: string;
  message: string;
  route?: string | null;
  operation?: string | null;
  context?: TelemetryContext;
}

const EMAIL = /[\w.%+-]+@[\w.-]+\.[A-Za-z]{2,}/g;
const MONEY = /\d{1,3}(,\d{3})+(\.\d+)?|\d+\.\d{2,}/g;
const LONG_DIGITS = /\d{7,}/g;
const UUID = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi;
const TOKENISH = /\b(ey[A-Za-z0-9._-]{20,}|sb[pk]_[A-Za-z0-9_-]{10,})\b/g;

/**
 * A message with everything private taken out of it.
 *
 * Order matters: tokens first (they contain digits), then emails, then anything
 * money-shaped, then any long run of digits, then ids. What survives is the
 * sentence — "Failed to settle [amount] for [email]" — which is what makes a
 * report useful without making it a leak.
 */
export function sanitiseMessage(input: unknown, limit = 500): string {
  const raw =
    typeof input === 'string'
      ? input
      : input instanceof Error
        ? `${input.message}`
        : String(input ?? 'Unknown error');

  return raw
    .replace(TOKENISH, '[token]')
    .replace(EMAIL, '[email]')
    .replace(MONEY, '[amount]')
    .replace(LONG_DIGITS, '[number]')
    .replace(UUID, '[id]')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, limit);
}

/** Only the whitelisted keys, only scalars, each one sanitised. */
export function sanitiseContext(context: TelemetryContext = {}): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of CONTEXT_KEYS) {
    const value = context[key];
    if (value === undefined || value === null) continue;
    if (typeof value === 'number' || typeof value === 'boolean') out[key] = value;
    else if (typeof value === 'string') out[key] = sanitiseMessage(value, 80);
  }
  return out;
}

/**
 * A route with its parameters removed.
 *
 * `/people/3f1a…-…` identifies a person; `/people/[id]` identifies a screen.
 * Only the second belongs in a crash report.
 */
export function sanitiseRoute(route: string | null | undefined): string | null {
  if (!route) return null;
  const path = route.split('?')[0] ?? route;
  return path
    .replace(UUID, '[id]')
    .replace(/\/\d+(?=\/|$)/g, '/[n]')
    .slice(0, 120);
}

/**
 * What groups repeats of one fault together.
 *
 * The sanitised message rather than a stack: a stack in a minified production
 * bundle is a list of one-letter function names, and it changes with every
 * deploy, so a hundred reports of one bug would read as a hundred bugs.
 */
export function fingerprint(report: ErrorReport): string {
  const shape = sanitiseMessage(report.message, 120)
    .toLowerCase()
    .replace(/\[(amount|email|number|id|token)\]/g, '')
    .replace(/[^a-z ]+/g, '')
    .split(' ')
    .filter(Boolean)
    .slice(0, 6)
    .join('-');

  return ['web', report.operation ?? 'unknown', report.errorType, shape]
    .join(':')
    .slice(0, 64);
}

/** The app version, as the build knows it. */
function appVersion(): string | null {
  return process.env.NEXT_PUBLIC_APP_VERSION ?? null;
}

function environment(): 'production' | 'development' | 'test' {
  if (process.env.NODE_ENV === 'production') return 'production';
  if (process.env.NODE_ENV === 'test') return 'test';
  return 'development';
}

/** True once per session after a send fails, so a dead sink is not retried forever. */
let sinkIsDown = false;

/**
 * Send one report.
 *
 * Never throws and never awaits anything the user is waiting on: telemetry that
 * can break the app it is reporting on is worse than no telemetry. A failure to
 * report is swallowed, once, and then the sink is left alone.
 */
export async function reportError(report: ErrorReport): Promise<void> {
  if (sinkIsDown) return;

  try {
    const supabase = createClient();
    const { error } = await supabase.rpc('report_client_error', {
      p_app: 'web',
      p_error_type: sanitiseMessage(report.errorType, 120) || 'Error',
      p_message: sanitiseMessage(report.message) || 'Unknown error',
      p_fingerprint: fingerprint(report),
      p_app_version: appVersion(),
      p_environment: environment(),
      p_route: sanitiseRoute(report.route),
      p_operation: report.operation ?? null,
      p_context: sanitiseContext(report.context),
    });

    // A rate limit is the system working, not a broken sink.
    if (error && error.code !== 'AC429') sinkIsDown = true;
  } catch {
    sinkIsDown = true;
  }
}

/** For tests: forget that the sink ever failed. */
export function resetTelemetry(): void {
  sinkIsDown = false;
}
