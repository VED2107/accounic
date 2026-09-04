import { NextResponse, type NextRequest } from 'next/server';

import { getMe } from '@/lib/supabase/server';
import { loadExport } from '@/lib/export/load';
import { csvWithBom } from '@/lib/export/csv';
import { activityEntriesToCsv } from '@/lib/export/activity-csv';
import { renderActivityPdf } from '@/lib/pdf/activity';
import { formatApprox, formatMoney } from '@/lib/money';
import {
  activityExportFilename,
  activityExportRequest,
  parseRange,
  parseView,
  rangeIsBackwards,
} from '@/lib/export/activity';

/**
 * Downloading the Activity feed (Activity → Export).
 *
 * A sibling of `/api/export`, not a branch of it. Both stream a file and both
 * go through `loadExport`, but they build different documents from the same
 * rows: that one is the workspace report, grouped by account; this one is the
 * Activity feed, grouped by day. Folding the two into one handler would have
 * meant a query string that decides the shape of the document, which is how a
 * route ends up with two ideas about what it returns.
 *
 * The request says which Activity view it came from and, optionally, which day.
 * It does NOT say what to filter on: this handler derives the filter contract
 * itself, so a hand-written query string cannot ask for a slice the screen
 * cannot show. Authorization is checked twice by construction — the session has
 * to resolve here, and the RPCs underneath are SECURITY INVOKER, so RLS decides
 * what is in the file regardless of what was asked for.
 */

/** Streaming a file is not a page: never cache one. */
export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  const me = await getMe();
  if (!me) {
    return NextResponse.json({ error: 'Sign in to export your activity.' }, { status: 401 });
  }

  const params = request.nextUrl.searchParams;
  const format: 'csv' | 'pdf' = params.get('format') === 'pdf' ? 'pdf' : 'csv';
  const view = parseView(params.get('view'));
  const range = parseRange(params.get('from'), params.get('to'));

  if (rangeIsBackwards(range)) {
    return NextResponse.json(
      { error: 'The start of the range is after its end. Swap the two dates and try again.' },
      { status: 400 },
    );
  }

  let bundle;
  try {
    bundle = await loadExport(activityExportRequest(view, range));
  } catch (error) {
    // The database's own message is the honest one for a bad filter, and it
    // never contains ledger data.
    const message = error instanceof Error ? error.message : 'The export could not be built.';
    return NextResponse.json({ error: message }, { status: 400 });
  }

  const filename = activityExportFilename(format, view, range);

  const body =
    format === 'pdf'
      ? Buffer.from(await renderActivityPdf(bundle, { view, range }))
      : csvWithBom(
          activityEntriesToCsv(
            bundle.entries,
            {
              // The same currency rule as the PDF and the screen: the base
              // currency is written with its symbol alone.
              money: (minor, currency, base) => formatMoney(minor, currency, { base }),
              approx: (minor, currency) => formatApprox(minor, currency),
            },
            bundle.header.workspace?.base_currency ?? 'INR',
          ),
        );

  return new NextResponse(body, {
    status: 200,
    headers: {
      'Content-Type':
        format === 'pdf' ? 'application/pdf' : 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="${filename}"`,
      // The file is the user's own books. It must not sit in a shared cache.
      'Cache-Control': 'no-store, private',
      'X-Accounic-Entries': String(bundle.entries.length),
      'X-Accounic-Truncated': bundle.truncated ? '1' : '0',
    },
  });
}
