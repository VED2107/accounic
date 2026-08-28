import { NextResponse } from 'next/server';
import { getMe } from '@/lib/supabase/server';
import { getPersonPage } from '@/lib/queries';
import { buildPersonStatement } from '@/lib/pdf/statement';
import type { PersonPage, TimelineEntry } from '@/lib/types';

/**
 * GET /people/:id/statement — the account statement as a PDF (upgrade §47).
 *
 * A route rather than a server action, because the answer is a file: the
 * browser has to be able to open it in a tab, and a server action cannot hand
 * back a download.
 *
 * Authorisation is the database's, not this handler's. `getPersonPage` calls
 * `person_page()` as the signed-in user, which is SECURITY INVOKER, so RLS
 * confines it to that user's own workspace. Asking for somebody else's person
 * id returns nothing here for the same reason it returns nothing on the screen
 * — there is no separate check to forget to write.
 */

/** `person_page()` caps a request at 100 rows; a statement wants all of them. */
const PAGE_SIZE = 100;
/** And a ceiling, so one enormous account cannot tie up a request forever. */
const MAX_ROWS = 2000;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;

  const [me, first] = await Promise.all([getMe(), getPersonPage(id, PAGE_SIZE, 0)]);
  if (!first) {
    return new NextResponse('Not found', { status: 404 });
  }

  // Page through the rest. The first call already told us how many there are,
  // so this loop is bounded by the data and by MAX_ROWS, never by a guess.
  const timeline: TimelineEntry[] = [...first.timeline];
  const total = Math.min(first.timeline_total ?? timeline.length, MAX_ROWS);

  for (let offset = PAGE_SIZE; offset < total; offset += PAGE_SIZE) {
    const next = await getPersonPage(id, PAGE_SIZE, offset);
    if (!next || next.timeline.length === 0) break;
    timeline.push(...next.timeline);
  }

  const page: PersonPage = { ...first, timeline };
  const truncated = (first.timeline_total ?? 0) > timeline.length;

  const pdf = await buildPersonStatement({
    page,
    me,
    truncated,
    rowsCovered: timeline.length,
  });

  const filename = `${slug(first.person.name)}-statement.pdf`;

  return new NextResponse(Buffer.from(pdf), {
    headers: {
      'Content-Type': 'application/pdf',
      // `inline` so the browser opens it, which is what a person checking a
      // balance wants; the filename is still there for whoever saves it.
      'Content-Disposition': `inline; filename="${filename}"`,
      // A statement is one user's private ledger. It must never sit in a shared
      // cache, and it must not be re-served after they sign out.
      'Cache-Control': 'private, no-store, max-age=0',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

/** A filename that is safe on every platform and still recognisable. */
function slug(name: string): string {
  const cleaned = name
    .normalize('NFKD')
    .replace(/[^\w\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .toLowerCase();
  return cleaned || 'account';
}
