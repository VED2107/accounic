import { NextResponse, type NextRequest } from 'next/server';

import { getMe } from '@/lib/supabase/server';
import { loadExport, type ExportRequest } from '@/lib/export/load';
import { csvWithBom, entriesToCsv } from '@/lib/export/csv';
import { buildExportDocument, exportDocumentToJson, exportFilename } from '@/lib/export/json';

/**
 * Downloading an export (milestone 1.9.0, Phase 5).
 *
 * A route handler rather than a server action, because the product of this
 * request is a file: the browser needs a Content-Disposition, and an action
 * returning a megabyte of CSV through a React payload would be the wrong shape
 * for it in every way.
 *
 * Authorization is the same as everywhere else and is checked twice by
 * construction: the session has to resolve here, and the RPCs underneath are
 * SECURITY INVOKER, so RLS decides what is in the file regardless of what the
 * query string asks for. A filter is a filter, never a way to widen access.
 */

/** Streaming a file is not a page: never cache one. */
export const dynamic = 'force-dynamic';

function parseRequest(params: URLSearchParams): ExportRequest {
  const scope = params.get('scope');
  const kinds = params.getAll('kind').filter(Boolean);

  return {
    from: params.get('from'),
    to: params.get('to'),
    personId: params.get('person'),
    currency: params.get('currency'),
    kinds: kinds.length > 0 ? kinds : null,
    scope: scope === 'opening' || scope === 'regular' ? scope : 'all',
    includeVoid: params.get('void') === '1',
  };
}

export async function GET(request: NextRequest) {
  const me = await getMe();
  if (!me) {
    return NextResponse.json({ error: 'Sign in to export your workspace.' }, { status: 401 });
  }

  const params = request.nextUrl.searchParams;
  const format = params.get('format') === 'json' ? 'json' : 'csv';

  let bundle;
  try {
    bundle = await loadExport(parseRequest(params));
  } catch (error) {
    // The database's own message is the honest one for a bad filter — an
    // unknown scope, an unparseable date — and it never contains ledger data.
    const message = error instanceof Error ? error.message : 'The export could not be built.';
    return NextResponse.json({ error: message }, { status: 400 });
  }

  const person = bundle.header.filters.person_id
    ? (bundle.header.people[0]?.name ?? null)
    : null;

  const filename = exportFilename(format, { scope: person });
  const body =
    format === 'json'
      ? exportDocumentToJson(buildExportDocument(bundle))
      : csvWithBom(entriesToCsv(bundle.entries));

  return new NextResponse(body, {
    status: 200,
    headers: {
      'Content-Type':
        format === 'json'
          ? 'application/json; charset=utf-8'
          : 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="${filename}"`,
      // The file is the user's own books. It must not sit in a shared cache.
      'Cache-Control': 'no-store, private',
      'X-Accounic-Entries': String(bundle.entries.length),
      'X-Accounic-Truncated': bundle.truncated ? '1' : '0',
    },
  });
}
