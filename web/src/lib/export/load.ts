import 'server-only';

import { createClient } from '@/lib/supabase/server';
import type {
  ExportBundle,
  ExportEntry,
  ExportEntryPage,
  ExportFilters,
  ExportHeader,
} from '@/lib/export/types';

/**
 * Fetching an export (milestone 1.9.0, Phases 4–6).
 *
 * Two RPCs and a loop. `export_workspace()` is one round trip; the ledger is
 * paged, because a workspace with fifty thousand entries must not become one
 * request that times out on a phone tethered to a train.
 *
 * Nothing here filters, sorts or computes: the database applies the filter
 * contract and returns entries in a deterministic order, and this walks the
 * pages until it has them. If it stops early, it says so — `truncated` — and
 * every writer prints that fact rather than quietly shipping a partial backup.
 */

/** The most entries a single export will assemble in memory. */
export const EXPORT_MAX_ENTRIES = 50_000;

/** The page size asked of `export_entries()`; its own cap is 5,000. */
const PAGE_SIZE = 2_000;

export interface ExportRequest {
  from?: string | null;
  to?: string | null;
  personId?: string | null;
  currency?: string | null;
  kinds?: string[] | null;
  scope?: 'all' | 'regular' | 'opening';
  includeVoid?: boolean;
}

function rpcArgs(request: ExportRequest): Record<string, unknown> {
  return {
    p_from: request.from ?? null,
    p_to: request.to ?? null,
    p_person_id: request.personId ?? null,
    p_currency: request.currency ?? null,
    p_kinds: request.kinds && request.kinds.length > 0 ? request.kinds : null,
    p_scope: request.scope ?? 'all',
    p_include_void: request.includeVoid ?? false,
  };
}

export async function getExportHeader(request: ExportRequest = {}): Promise<ExportHeader> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('export_workspace', rpcArgs(request));
  if (error) throw error;
  return data as ExportHeader;
}

export async function getExportEntryPage(
  request: ExportRequest,
  offset: number,
  limit = PAGE_SIZE,
): Promise<ExportEntryPage> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('export_entries', {
    ...rpcArgs(request),
    p_limit: limit,
    p_offset: offset,
  });
  if (error) throw error;
  return data as ExportEntryPage;
}

/** The header and every entry it describes, paged until there are no more. */
export async function loadExport(request: ExportRequest = {}): Promise<ExportBundle> {
  const header = await getExportHeader(request);

  const entries: ExportEntry[] = [];
  let truncated = false;
  let offset = 0;

  for (;;) {
    const page = await getExportEntryPage(request, offset);
    entries.push(...page.entries);

    if (!page.has_more) break;
    if (entries.length >= EXPORT_MAX_ENTRIES) {
      truncated = true;
      break;
    }
    offset += page.limit;
  }

  return { header, entries, truncated };
}

/** The filters as the database normalised them — what the file should say it holds. */
export function describeFilters(filters: ExportFilters): string {
  const parts: string[] = [];
  if (filters.from || filters.to) {
    parts.push(`${filters.from ?? 'the beginning'} to ${filters.to ?? 'today'}`);
  }
  if (filters.currency) parts.push(`entered in ${filters.currency}`);
  if (filters.kinds && filters.kinds.length > 0) parts.push(filters.kinds.join(', '));
  if (filters.scope === 'opening') parts.push('opening balances only');
  if (filters.scope === 'regular') parts.push('excluding opening balances');
  if (filters.include_void) parts.push('including voided history');
  return parts.length === 0 ? 'Everything' : parts.join(' · ');
}
