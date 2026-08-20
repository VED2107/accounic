/**
 * The shared backend contract (context.md §21, Deliverables #12).
 *
 * These types mirror the SQL in db/migrations one-for-one. The Dart mirror
 * lives in app/lib/data/models/ — when a shape changes here, change it there.
 * Amounts named *_minor are always integer minor units.
 */

export type PartyType = 'person' | 'business';
export type TxnType = 'credit' | 'debit';
export type SettlementDirection = 'in' | 'out';
export type EntryKind = 'transaction' | 'settlement';
export type SettlementStatus = 'open' | 'partial' | 'settled';

export interface Me {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  business_name: string | null;
  avatar_url: string | null;
  currency: string;
  is_active: boolean;
  is_admin: boolean;
  created_at: string;
}

export interface Person {
  id: string;
  owner_id: string;
  name: string;
  type: PartyType;
  phone: string | null;
  email: string | null;
  address: string | null;
  notes: string | null;
  is_archived: boolean;
  created_at: string;
  updated_at: string;
}

/** public.person_balances — the authoritative per-person position. */
export interface PersonBalance {
  person_id: string;
  owner_id: string;
  name: string;
  type: PartyType;
  phone: string | null;
  email: string | null;
  is_archived: boolean;
  total_credit: number;
  total_debit: number;
  settled_in: number;
  settled_out: number;
  total_settled: number;
  outstanding_receivable: number;
  outstanding_payable: number;
  net_balance: number;
  transaction_count: number;
  last_activity_at: string | null;
}

/** public.owner_summary — dashboard headline numbers. */
export interface OwnerSummary {
  owner_id: string;
  total_receivable: number;
  total_payable: number;
  net_position: number;
  people_with_balance: number;
  people_count: number;
  gross_credit: number;
  gross_debit: number;
  gross_settled: number;
}

export interface TimelineEntry {
  id: string;
  entry_kind: EntryKind;
  /** 'credit' | 'debit' for transactions, 'in' | 'out' for settlements. */
  entry_type: string;
  money_direction: SettlementDirection;
  amount_minor: number;
  entry_date: string;
  note: string | null;
  is_void: boolean;
  related_transaction_id: string | null;
  created_at: string;
  /** Present only on transaction entries. */
  settled_minor: number | null;
  remaining_minor: number | null;
  status: SettlementStatus | null;
}

export interface OpenTransaction {
  id: string;
  type: TxnType;
  amount_minor: number;
  transaction_date: string;
  description: string | null;
  remaining_minor: number;
  settled_minor: number;
}

/** public.person_page() */
export interface PersonPage {
  person: Person;
  balance: PersonBalance;
  timeline: TimelineEntry[];
  timeline_total: number;
  open_transactions: OpenTransaction[];
}

export interface ActivityItem {
  id: string;
  person_id: string;
  person_name: string;
  entry_kind: EntryKind;
  entry_type: string;
  amount_minor: number;
  entry_date: string;
  note: string | null;
  created_at: string;
}

export interface DashboardPeopleRow {
  person_id: string;
  name: string;
  type: PartyType;
  net_balance: number;
  outstanding_receivable: number;
  outstanding_payable: number;
  last_activity_at: string | null;
}

/** public.dashboard() */
export interface Dashboard {
  profile: Pick<Me, 'id' | 'name' | 'email' | 'phone' | 'business_name' | 'avatar_url' | 'currency'>;
  summary: OwnerSummary;
  today: { credit: number; debit: number; settled: number; count: number };
  recent_activity: ActivityItem[];
  people_with_balance: DashboardPeopleRow[];
}

/** public.search_all() */
export interface SearchResults {
  people: Array<{
    person_id: string;
    name: string;
    type: PartyType;
    phone: string | null;
    net_balance: number;
    is_archived: boolean;
  }>;
  transactions: Array<{
    id: string;
    person_id: string;
    person_name: string;
    type: TxnType;
    amount_minor: number;
    transaction_date: string;
    description: string | null;
  }>;
}

export interface AdminUser {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  business_name: string | null;
  currency: string;
  is_active: boolean;
  is_admin: boolean;
  created_at: string;
  updated_at: string;
  last_sign_in_at: string | null;
  people_count: number;
  transaction_count: number;
}

export interface AdminUserList {
  total: number;
  users: AdminUser[];
}

export interface AdminSystemInfo {
  users_total: number;
  users_active: number;
  admins: number;
  people_total: number;
  transactions_total: number;
  settlements_total: number;
  database_size: string;
  server_time: string;
}

/** Envelope returned by the mutation RPCs so a client can reconcile at once. */
export interface MutationResult<T> {
  balance: PersonBalance | null;
  transaction?: T;
  settlement?: T;
}

/** Uniform shape returned by every server action (context.md §26). */
export type ActionResult<T = void> =
  | { ok: true; data: T }
  | { ok: false; error: string; field?: string };
