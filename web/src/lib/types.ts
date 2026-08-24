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
  /**
   * The person's DEFAULT ENTRY currency: what a new transaction with them is
   * entered in. NULL means the owner's base currency — see db/migrations/0010.
   * Changing it never rewrites history (db/migrations/0013).
   */
  currency: string | null;
  /**
   * The currency this person's stored figures are denominated in, frozen the
   * first time `currency` moved away from it. NULL means the two have never
   * diverged, so the ledger simply follows `currency`.
   */
  ledger_currency: string | null;
  is_archived: boolean;
  created_at: string;
  updated_at: string;
}

/** Which way an opening balance runs, in the user's words (upgrade §3). */
export type OpeningDirection = 'none' | 'they_owe_me' | 'i_owe_them';

/** Conversion provenance, carried by any row entered in another currency. */
export interface Conversion {
  entered_amount_minor: number | null;
  entered_currency: string | null;
  exchange_rate_e9: number | null;
  exchange_rate_at?: string | null;
  exchange_rate_source?: string | null;
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
  /**
   * The currency every figure in this row is denominated in — the person's
   * ledger currency, already resolved.
   */
  currency: string;
  /** What a new entry for this person should default to. May differ. */
  default_currency: string;
  base_currency: string;
  total_credit: number;
  total_debit: number;
  settled_in: number;
  settled_out: number;
  total_settled: number;
  outstanding_receivable: number;
  outstanding_payable: number;
  net_balance: number;
  /** The same net position in the base currency, or null when no rate is known. */
  net_balance_base: number | null;
  /**
   * And in the person's own default currency. Display only — it moves when
   * rates move, and equals net_balance whenever the two currencies agree.
   */
  net_balance_default: number | null;
  transaction_count: number;
  /** The opening balance as a signed figure: positive when they owe the user. */
  opening_minor: number;
  last_activity_at: string | null;
}

/** public.owner_summary — dashboard headline numbers. */
export interface OwnerSummary {
  owner_id: string;
  base_currency: string;
  total_receivable: number;
  total_payable: number;
  net_position: number;
  people_with_balance: number;
  people_count: number;
  gross_credit: number;
  gross_debit: number;
  gross_settled: number;
  /** People whose currency has no cached rate, and are therefore not in the totals. */
  unconverted_people: number;
  currency_count: number;
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
  is_opening: boolean;
  entered_amount_minor: number | null;
  entered_currency: string | null;
  exchange_rate_e9: number | null;
  exchange_rate_at: string | null;
  exchange_rate_source: string | null;
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
  is_opening: boolean;
  remaining_minor: number;
  settled_minor: number;
}

/** public.person_page() */
export interface PersonPage {
  person: Person;
  balance: PersonBalance;
  /** What the figures on this page are denominated in. */
  currency: string;
  /** What a new entry for this person should default to. */
  default_currency: string;
  base_currency: string;
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
  /** The currency this row is denominated in — the person's, not the owner's. */
  currency: string;
  is_opening?: boolean;
  entered_amount_minor?: number | null;
  entered_currency?: string | null;
  exchange_rate_e9?: number | null;
}

export interface DashboardPeopleRow {
  person_id: string;
  name: string;
  type: PartyType;
  currency: string;
  default_currency?: string;
  base_currency: string;
  net_balance: number;
  net_balance_base: number | null;
  outstanding_receivable: number;
  outstanding_payable: number;
  last_activity_at: string | null;
}

/** public.dashboard() */
export interface Dashboard {
  profile: Pick<Me, 'id' | 'name' | 'email' | 'phone' | 'business_name' | 'avatar_url' | 'currency'>;
  base_currency: string;
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
    net_balance_base: number | null;
    currency: string;
    base_currency: string;
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
    currency: string;
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
