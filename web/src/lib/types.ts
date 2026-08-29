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
  /**
   * 'automatic' | 'manual' | null (upgrade §40). Null means the row was never
   * converted; a pre-v1.1.2 converted row reads as 'automatic', because the
   * feed resolves that rather than passing its stored NULL through.
   */
  conversion_mode?: ConversionMode | null;
  /**
   * What the recorded rate said the entry was worth. Present only on a manual
   * row, where `amount_minor` is instead what actually changed hands.
   */
  auto_converted_amount_minor?: number | null;
}

/** Which of the two figures `amount_minor` is (upgrade §40). */
export type ConversionMode = 'automatic' | 'manual';

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

  /**
   * The two halves of net_balance (db/migrations/0022).
   *
   *     cash_in_hand_minor + opening_net_minor === net_balance
   *
   * always, and the database asserts it. `cash_in_hand_minor` is the regular
   * trading position and never contains the opening balance; `opening_net_minor`
   * is what is left of the opening book. They are shown as two figures and never
   * added together on screen.
   */
  cash_in_hand_minor: number;
  cash_in_hand_base: number | null;
  opening_net_minor: number;
  opening_net_base: number | null;

  regular_credit_minor: number;
  regular_debit_minor: number;
  regular_receivable: number;
  regular_payable: number;
  regular_settled_total: number;

  opening_credit_minor: number;
  opening_debit_minor: number;
  opening_receivable: number;
  opening_payable: number;
  opening_settled_total: number;
  /** Rows in the opening book. Zero means the account has no opening balance. */
  opening_entry_count: number;
}

/**
 * One of the two positions an account holds (db/migrations/0022).
 *
 * `person_page()` states both outright — the cash-in-hand position under
 * `regular`, the opening book's under `opening_position` — so that no client
 * subtracts one from the other and no two clients can disagree about which is
 * which.
 */
export interface PositionSplit {
  currency: string;
  base_currency: string;
  /** Signed: positive when they owe the user. */
  position: number;
  position_base: number | null;
  receivable: number;
  payable: number;
  settled: number;
  credit: number;
  debit: number;
  entry_count?: number;
}

/** One workspace-level total, in the workspace currency (db/migrations/0022). */
export interface WorkspacePosition {
  base_currency: string;
  position: number;
  receivable: number;
  payable: number;
  settled: number;
  today: number;
  today_count: number;
  people_count: number;
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
  /**
   * Which part of the opening book this row is: 'balance' for what the account
   * opened with, 'adjustment' for a credit or debit recorded against it. Null
   * on a settlement and on every ordinary transaction (db/migrations/0022).
   */
  opening_role?: 'balance' | 'adjustment' | null;
  /**
   * True when the row belongs to the opening book at all — including a
   * settlement made against the opening balance, which is not itself flagged.
   * The regular timeline holds no row for which this is true.
   */
  opening_scope?: boolean;
  entered_amount_minor: number | null;
  entered_currency: string | null;
  exchange_rate_e9: number | null;
  exchange_rate_at: string | null;
  exchange_rate_source: string | null;
  conversion_mode: ConversionMode | null;
  auto_converted_amount_minor: number | null;
  /**
   * What was actually entered, and what the ledger figure is worth in the
   * workspace currency (db/migrations/0018).
   *
   * `amount_minor` above stays the ledger figure — the one every balance is
   * summed from. These three exist so the row can show the original amount as
   * the headline and its base-currency equivalent underneath without any client
   * converting anything itself. Optional: a client running against a database
   * older than 0018 sees them absent and falls back to the ledger figure, which
   * is what it showed before.
   */
  entry_amount_minor?: number | null;
  entry_currency?: string | null;
  ledger_currency?: string | null;
  amount_base_minor?: number | null;
  base_currency?: string | null;
  /**
   * The transfer this row is one half of (db/migrations/0020).
   *
   * Null on an ordinary entry, which is every entry written before transfers
   * existed. `transfer_role` says which side of it this row is, and the
   * counterparty is the OTHER person — the one this money went to or came from.
   */
  transfer_id?: string | null;
  transfer_role?: TransferRole | null;
  transfer_counterparty_id?: string | null;
  transfer_counterparty_name?: string | null;
  /** Present only on transaction entries. */
  settled_minor: number | null;
  remaining_minor: number | null;
  status: SettlementStatus | null;
}

/** Which side of a transfer a ledger row is (db/migrations/0020). */
export type TransferRole = 'source' | 'destination';

/**
 * public.person_opening — what an account was carried in with (0019).
 *
 * Its own section on the person page, never a row in the timeline. It is still
 * a transaction underneath, so it still counts towards `net_balance` exactly as
 * it always has; what changed is that it is no longer presented as something
 * that happened on a particular Tuesday, and it can no longer be settled as an
 * individual transaction.
 */
export interface PersonOpening {
  person_id: string;
  owner_id: string;
  transaction_id: string;
  entry_type: TxnType;
  /** Positive when they owe the user, negative when the user owes them. */
  signed_minor: number;
  /** The same figure unsigned, in the account's ledger currency. */
  amount_minor: number;
  ledger_currency: string;
  /** What was actually entered, and in what. */
  entry_amount_minor: number;
  entry_currency: string;
  /** Its value in the workspace currency. Null when no rate is known. */
  amount_base_minor: number | null;
  base_currency: string;
  entered_amount_minor: number | null;
  entered_currency: string | null;
  exchange_rate_e9: number | null;
  exchange_rate_at: string | null;
  exchange_rate_source: string | null;
  /** Whether a human typed that rate. Resolved by public.rate_is_manual(). */
  rate_is_manual: boolean;
  conversion_mode: ConversionMode | null;
  auto_converted_amount_minor: number | null;
  entry_date: string;
  note: string | null;
  created_at: string;
  /**
   * Where the opening balance's OWN settlement stands (db/migrations/0021).
   *
   * An opening balance is settled through its own action, not through the row
   * action the regular transactions use — two sections, two settlement paths,
   * one page. These come from the same FIFO allocator every other row reads.
   */
  settled_minor: number;
  remaining_minor: number;
  status: SettlementStatus;
}

/**
 * One superseded opening balance, kept because replacing one retracts it.
 *
 * Since db/migrations/0022 it carries `transaction_id` as well as `id`, so it
 * has the same shape as `PersonOpening` and one model can parse both. That was
 * not cosmetic: the Flutter client parsed both with one model whose
 * `transaction_id` was non-nullable, and the first time a user edited an
 * opening balance — the moment this list stops being empty — the person screen
 * stopped loading entirely.
 */
export interface OpeningHistoryEntry {
  id: string;
  /** The same row's id, under the key `PersonOpening` uses (0022). */
  transaction_id?: string;
  /** Positive when they owed the user (0022). */
  signed_minor?: number;
  amount_minor: number;
  entry_type: TxnType;
  entry_date: string;
  created_at: string;
  entry_amount_minor: number;
  entry_currency: string;
  ledger_currency: string;
  amount_base_minor: number | null;
  base_currency: string;
  entered_amount_minor: number | null;
  entered_currency: string | null;
  exchange_rate_e9: number | null;
  exchange_rate_source: string | null;
  conversion_mode: ConversionMode | null;
  auto_converted_amount_minor: number | null;
}

/**
 * public.transfers — one movement of money between two people (0020).
 *
 * Three amounts, because a cross-currency transfer has three: what the user
 * typed, what left the source in its own denomination, and what reached the
 * destination in its own. For a single-currency transfer all three are the same
 * number, which the database enforces with a CHECK constraint.
 */
export interface Transfer {
  id: string;
  owner_id: string;
  from_person_id: string;
  to_person_id: string;
  transfer_date: string;
  note: string | null;
  entry_amount_minor: number;
  entry_currency: string;
  from_amount_minor: number;
  from_currency: string;
  to_amount_minor: number;
  to_currency: string;
  /** entry currency → source ledger currency. Null when they are the same. */
  entry_rate_e9: number | null;
  /** source ledger currency → destination ledger currency. */
  exchange_rate_e9: number | null;
  exchange_rate_at: string | null;
  exchange_rate_source: string | null;
  conversion_mode: ConversionMode | null;
  auto_converted_amount_minor: number | null;
  client_token: string | null;
  is_void: boolean;
  void_reason: string | null;
  created_at: string;
  updated_at: string;
}

/** What every transfer RPC returns: the record, and both sides' balances. */
export interface TransferResult {
  transfer: Transfer;
  from_person: Person | null;
  to_person: Person | null;
  from_balance: PersonBalance | null;
  to_balance: PersonBalance | null;
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
  /**
   * The opening balance, in its own section (db/migrations/0019). Null when the
   * account has none — which is not the same as zero and reads differently.
   */
  opening: PersonOpening | null;
  /** Opening balances that were replaced. They affect no balance. */
  opening_history: OpeningHistoryEntry[];
  /**
   * Credits, debits and settlements recorded against the opening balance
   * (db/migrations/0022). Deliberately absent from `timeline`: they are not
   * regular transactions and must never be shown among them.
   */
  opening_activity: TimelineEntry[];
  /** The regular trading position — cash in hand. Never contains the opening balance. */
  regular: PositionSplit;
  /** The opening book's position, on its own. Never added into `regular` on screen. */
  opening_position: PositionSplit;
  /** Regular activity only: credits, debits, settlements and transfer legs. */
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
  /**
   * What was actually entered, and in what (0017). This is the amount the user
   * typed and recognises, so it is the one to show: on a rupee account a USD 40
   * entry has `entry_amount_minor` 4000 / `entry_currency` USD, while
   * `amount_minor` holds the ₹ figure it was converted into. Equal to
   * amount_minor/currency whenever the entry needed no conversion.
   */
  entry_amount_minor?: number;
  entry_currency?: string;
  /**
   * The row's value in the workspace currency, converted by the engine.
   * Supplementary information shown beside the original — never in place of it.
   * Null when no rate is cached.
   */
  amount_base_minor?: number | null;
  base_currency?: string;
  is_opening?: boolean;
  entered_amount_minor?: number | null;
  entered_currency?: string | null;
  exchange_rate_e9?: number | null;
  /** 'live', a cache label, or the marker a hand-typed rate is stored under. */
  exchange_rate_source?: string | null;
  conversion_mode?: ConversionMode | null;
  auto_converted_amount_minor?: number | null;
  /** The transfer this row is one leg of, and who the other party is (0020). */
  transfer_id?: string | null;
  transfer_role?: TransferRole | null;
  transfer_counterparty_id?: string | null;
  transfer_counterparty_name?: string | null;
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

/**
 * One currency's standing position, in that currency (0015).
 *
 * Never converted and never summed with another row: the base-currency answer
 * is `OwnerSummary`, and this is the same money read in the denomination it was
 * actually entered in.
 */
export interface CurrencyTotals {
  /** The currency entries were actually made in — not the account's. */
  currency: string;
  /** The workspace currency the equivalent below is stated in. */
  base_currency: string;
  gross_credit: number;
  gross_debit: number;
  gross_settled: number;
  /** credit - debit, in `currency`. Never mixed with another currency. */
  net_position: number;
  /**
   * `net_position` converted to `base_currency` by the engine's own converter.
   * Supplementary — the figure above is the real one. Null when no rate is
   * cached, which means "not known", never zero.
   */
  net_base_minor: number | null;
  entry_count: number;
  people_count: number;
}

/** Today's movement in one currency (0015). */
export interface CurrencyToday {
  currency: string;
  base_currency: string;
  credit: number;
  debit: number;
  settled: number;
  count: number;
  /** Everything that moved today in this currency, converted to base. */
  moved_base_minor: number | null;
}

/** public.dashboard() */
export interface Dashboard {
  profile: Pick<Me, 'id' | 'name' | 'email' | 'phone' | 'business_name' | 'avatar_url' | 'currency'>;
  base_currency: string;
  summary: OwnerSummary;
  today: { credit: number; debit: number; settled: number; count: number };
  /**
   * The consolidated regular position, converted to the workspace currency
   * (db/migrations/0022). Never contains an opening balance.
   */
  cash_in_hand: WorkspacePosition;
  /**
   * The opening book's position, calculated independently and shown beside
   * `cash_in_hand` — never inside it. The two add up to `summary.net_position`.
   */
  opening: WorkspacePosition;
  /** Only currencies that carry entries. Empty on a workspace with none. */
  totals_by_currency: CurrencyTotals[];
  today_by_currency: CurrencyToday[];
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
