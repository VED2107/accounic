import 'server-only';

import { createClient, getMe } from '@/lib/supabase/server';
import type {
  ActivityItem,
  AdminSystemInfo,
  AdminUserList,
  Dashboard,
  PersonBalance,
  PersonPage,
  SearchResults,
} from '@/lib/types';

/**
 * Server-side reads (context.md §23).
 *
 * Each screen is one round trip: the heavy pages call a single RPC that returns
 * its whole payload, instead of a query per widget. Nothing here recomputes a
 * balance — every number comes from the views in db/migrations/0003.
 */

export async function getDashboard(): Promise<Dashboard> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('dashboard', {
    p_activity_limit: 12,
    p_people_limit: 8,
  });
  if (error) throw error;
  return data as Dashboard;
}

export interface PeopleListOptions {
  query?: string;
  includeArchived?: boolean;
  sort?: 'name' | 'balance' | 'recent';
}

export async function getPeople(options: PeopleListOptions = {}): Promise<PersonBalance[]> {
  const { query = '', includeArchived = false, sort = 'name' } = options;
  const supabase = await createClient();

  let request = supabase.from('person_balances').select('*');
  if (!includeArchived) request = request.eq('is_archived', false);
  if (query.trim()) {
    const escaped = query.trim().replace(/[%,()]/g, '');
    if (escaped) request = request.or(`name.ilike.%${escaped}%,phone.ilike.%${escaped}%`);
  }

  switch (sort) {
    case 'recent':
      request = request.order('last_activity_at', { ascending: false, nullsFirst: false });
      break;
    case 'balance':
      // Sorted client-side by |net| because Postgrest cannot order by an
      // expression; the list is bounded and this avoids a bespoke view.
      request = request.order('name');
      break;
    default:
      request = request.order('name');
  }

  const { data, error } = await request.limit(500);
  if (error) throw error;

  const rows = (data ?? []) as PersonBalance[];
  if (sort === 'balance') {
    rows.sort((a, b) => Math.abs(b.net_balance) - Math.abs(a.net_balance));
  }
  return rows;
}

export async function getPersonPage(
  personId: string,
  limit = 30,
  offset = 0,
): Promise<PersonPage | null> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('person_page', {
    p_person_id: personId,
    p_limit: limit,
    p_offset: offset,
  });
  if (error) {
    if (error.code === 'P0002' || error.code === '22P02') return null;
    throw error;
  }
  return data as PersonPage;
}

export async function search(query: string): Promise<SearchResults> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('search_all', { p_query: query, p_limit: 12 });
  if (error) throw error;
  return data as SearchResults;
}

export interface ActivityPage {
  items: ActivityItem[];
  total: number;
  has_more: boolean;
}

export async function getActivity(
  page = 0,
  pageSize = 40,
  kind?: 'transaction' | 'settlement',
): Promise<ActivityPage> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('activity_page', {
    p_limit: pageSize,
    p_offset: page * pageSize,
    p_kind: kind ?? null,
  });
  if (error) throw error;
  return data as ActivityPage;
}

export interface ActivityBucket {
  bucket: string;
  credit: number;
  debit: number;
  settled: number;
  entries: number;
}

export async function getActivitySummary(
  bucket: 'day' | 'week' | 'month' = 'day',
  days = 30,
): Promise<ActivityBucket[]> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('activity_summary', {
    p_bucket: bucket,
    p_days: days,
  });
  if (error) throw error;
  return (data ?? []) as ActivityBucket[];
}

/* ---------------------------------------------------------------------------
 * Admin reads. Each RPC re-checks is_admin() in the database, so this guard is
 * defence in depth rather than the only check (context.md §25).
 * ------------------------------------------------------------------------- */

export async function requireAdmin() {
  const me = await getMe();
  if (!me?.is_admin) throw new Error('Administrator access is required.');
  return me;
}

export async function getAdminUsers(query = ''): Promise<AdminUserList> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('admin_list_users', {
    p_query: query,
    p_limit: 100,
    p_offset: 0,
  });
  if (error) throw error;
  return data as AdminUserList;
}

export async function getAdminSystemInfo(): Promise<AdminSystemInfo> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc('admin_system_info');
  if (error) throw error;
  return data as AdminSystemInfo;
}
