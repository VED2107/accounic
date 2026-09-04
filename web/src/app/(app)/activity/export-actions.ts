'use server';

import { getExportHeader } from '@/lib/export/load';
import {
  activityExportRequest,
  type ActivityRange,
  type ActivityView,
} from '@/lib/export/activity';
import { friendlyMessage } from '@/lib/errors';

/**
 * How many entries an Activity export will contain.
 *
 * Asked for when the dialog opens, and again whenever the date or the category
 * changes, rather than rendered with the page: a screen nobody exports from should not pay for
 * the count, and the dialog can honestly say "Counting…" while it waits. It
 * never guesses — until this resolves, the dialog states no number at all.
 *
 * The figure is `export_workspace()`'s own count for exactly the filters the
 * download will use, so the number above the button and the number of rows in
 * the file are one number, computed once, by the database.
 *
 * SECURITY INVOKER all the way down: RLS decides what is countable, the same as
 * it decides what is exportable.
 */
export async function countActivityForExport(
  view: ActivityView,
  range: ActivityRange,
): Promise<{ ok: true; count: number } | { ok: false; error: string }> {
  try {
    const header = await getExportHeader(activityExportRequest(view, range));
    return { ok: true, count: header.counts.entries };
  } catch (error) {
    return {
      ok: false,
      error: friendlyMessage(error, 'The size of this export could not be checked.'),
    };
  }
}
