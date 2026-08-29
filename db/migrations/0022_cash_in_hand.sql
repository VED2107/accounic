-- =============================================================================
-- 0022 — cash in hand and the opening balance are two positions, not one
--
-- THREE THINGS ARE WRONG BEFORE THIS FILE
--
--   1. `person_page()` serves `opening_history` rows keyed on `id`, while every
--      other opening-balance payload is keyed on `transaction_id`. The Flutter
--      client parses both with one model, whose `transaction_id` is a
--      non-nullable String — so the first time a user edits an opening balance
--      (which retracts the old one and therefore fills `opening_history`), the
--      person screen stops loading with "That account could not be loaded."
--      Nothing is wrong with the data. The page cannot be parsed.
--
--   2. The opening balance is summed into every headline figure with no way to
--      take it back out. `person_balances.opening_minor` says what it was, but
--      nothing says what the account's position would be WITHOUT it, so no
--      screen can show the regular trading position on its own.
--
--   3. An opening balance can only be settled. There is no way to say "that
--      carried-in figure was 1,000 short" without recording a credit that then
--      reads as ordinary trading activity on the timeline.
--
-- WHAT THIS FILE ADDS
--
--   §1  `transactions.opening_role` — 'balance' | 'adjustment'. The opening
--       balance becomes a small BOOK rather than a single row: one balance row,
--       plus any number of adjustments. Backfilled for every existing opening
--       balance, which all become 'balance'.
--
--   §2  `activity_feed.opening_scope` — one boolean that answers "does this row
--       belong to the opening book?" for transactions AND for settlements. A
--       settlement is in the opening book when it names an opening transaction.
--       This is derived, never stored, so every historical row is classified by
--       the same rule the moment this file runs. Nothing is backfilled because
--       nothing needs to be.
--
--   §3  `person_balances` gains the split: `cash_in_hand_minor` (the regular
--       position) and `opening_net_minor` (the opening book's), plus the
--       receivable/payable/settled halves of each.
--
--       THE INVARIANT, asserted in §9 and in db/tests/11:
--
--           cash_in_hand_minor + opening_net_minor = net_balance
--
--       so the two displayed figures add up to the position that was always
--       there. Neither is double-counted, and `net_balance` is the same integer
--       after this file as before it.
--
--   §4  `owner_summary` and §5 `dashboard()` carry the same split to the
--       workspace level.
--
--   §6  `person_page()`: `opening_history` keyed correctly (the bug in 1),
--       `opening_activity` added, and `timeline` narrowed to `not opening_scope`
--       so an opening balance's own settlement stops appearing among the
--       regular transactions.
--
--   §7  `adjust_opening_balance()` — credit and debit against the opening book.
--   §8  `settle_opening_balance()` rewritten to settle the book, not one row.
--
-- WHAT IT DOES NOT CHANGE
--
-- No amount, currency, rate, date or id is rewritten. `net_balance`,
-- `total_credit`, `total_debit`, `settled_in`, `settled_out` and
-- `opening_minor` are the same integers as before. The direction semantics are
-- untouched: `type = 'credit'` still means receivable, exactly as
-- docs/accounting-direction.md records, and the opening book's credit and debit
-- go through the same enum the rest of the ledger does.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. The opening balance becomes a book
--
-- `opening_role` is not null exactly when `is_opening` is true, which the CHECK
-- enforces in both directions. Every row that exists today is a 'balance' — the
-- backfill says so out loud rather than assuming it — and the unique index that
-- used to mean "one opening row per person" now means "one opening BALANCE per
-- person", which is what it was always for.
-- -----------------------------------------------------------------------------

alter table public.transactions
  add column if not exists opening_role text;

-- `transactions_immutable_keys` refuses any UPDATE to a row that is already
-- void, which is right for a ledger and wrong for exactly this: filling in a
-- classification column that did not exist when the row was written. The two
-- statements below set `opening_role` and nothing else — no amount, no
-- currency, no rate, no date, no direction, no void flag — so the guard is
-- suspended for the length of the backfill and restored immediately, inside
-- the same transaction. A retracted opening balance must be classified too, or
-- `opening_history` cannot be served.
alter table public.transactions disable trigger transactions_immutable_keys;

update public.transactions
   set opening_role = 'balance'
 where is_opening and opening_role is null;

update public.transactions
   set opening_role = null
 where not is_opening and opening_role is not null;

-- The backfill queues the two DEFERRABLE constraint triggers on this table, and
-- ALTER TABLE refuses to run while their events are pending. Firing them now
-- both clears the queue and checks, before anything else in this file runs,
-- that the backfill left every settlement and every transfer leg valid.
set constraints all immediate;

alter table public.transactions enable trigger transactions_immutable_keys;

do $$
declare v_balances bigint;
begin
  select count(*) into v_balances from public.transactions where is_opening;
  raise notice
    '0022 §1: % opening row(s) classified as ''balance''. No amount, currency, rate or date altered.',
    v_balances;
end $$;

alter table public.transactions
  drop constraint if exists transactions_opening_role_valid;
alter table public.transactions
  add constraint transactions_opening_role_valid check (
    (is_opening = (opening_role is not null))
    and (opening_role is null or opening_role in ('balance', 'adjustment'))
  );

comment on column public.transactions.opening_role is
  'Which part of the opening book this row is: ''balance'' is what the account was carried in with, ''adjustment'' is a later correction to it. Null for ordinary trading rows (0022).';

-- One opening BALANCE per person. Adjustments are unlimited, and a retracted
-- balance still does not count — so a mistaken opening balance can be replaced
-- exactly as it could before.
drop index if exists public.transactions_one_opening_per_person;
create unique index if not exists transactions_one_opening_per_person
  on public.transactions (person_id)
  where is_opening and opening_role = 'balance' and not is_void;

-- The opening book is read per person constantly; this keeps that a lookup.
create index if not exists transactions_opening_book_idx
  on public.transactions (person_id, opening_role)
  where is_opening and not is_void;

-- -----------------------------------------------------------------------------
-- 2. `opening_scope` — one rule, applied to both halves of the feed
--
-- A transaction is in the opening book when it is flagged. A settlement is in
-- the opening book when it names a transaction that is flagged — including a
-- retracted one, because a settlement recorded against an opening balance that
-- was later replaced was still a payment against the opening balance, and
-- moving it into the regular timeline would misstate what happened.
--
-- The views are dropped and rebuilt rather than replaced: `activity_entries`
-- selects `a.*`, so a column added to `activity_feed` lands in the middle of
-- its column list and CREATE OR REPLACE VIEW refuses that.
-- -----------------------------------------------------------------------------

drop view if exists public.person_opening;
drop view if exists public.activity_entries;
drop view if exists public.activity_feed;

create view public.activity_feed
with (security_invoker = true) as
select
  t.id,
  t.owner_id,
  t.person_id,
  'transaction'::text                                   as entry_kind,
  t.type::text                                          as entry_type,
  case t.type when 'credit' then 'in' else 'out' end    as money_direction,
  t.amount_minor,
  t.transaction_date                                    as entry_date,
  t.description                                         as note,
  t.is_void,
  t.is_opening,
  t.entered_amount_minor,
  t.entered_currency,
  t.exchange_rate_e9,
  t.exchange_rate_at,
  t.exchange_rate_source,
  t.conversion_mode,
  t.auto_converted_amount_minor,
  null::uuid                                            as related_transaction_id,
  t.created_at,
  t.transfer_id,
  t.transfer_role,
  case t.transfer_role
    when 'source'      then tf.to_person_id
    when 'destination' then tf.from_person_id
  end                                                   as transfer_counterparty_id,
  t.opening_role,
  t.is_opening                                          as opening_scope
from public.transactions t
left join public.transfers tf on tf.id = t.transfer_id
union all
select
  s.id,
  s.owner_id,
  s.person_id,
  'settlement'::text,
  s.direction::text,
  s.direction::text,
  s.amount_minor,
  s.settlement_date,
  s.note,
  s.is_void,
  false,
  s.entered_amount_minor,
  s.entered_currency,
  s.exchange_rate_e9,
  s.exchange_rate_at,
  s.exchange_rate_source,
  s.conversion_mode,
  s.auto_converted_amount_minor,
  s.transaction_id,
  s.created_at,
  null::uuid,
  null::text,
  null::uuid,
  null::text,
  -- A settlement belongs to the opening book when it names an opening row.
  -- Account-level settlements (transaction_id null) are regular: they are a
  -- payment against the account as a whole, not against what it opened with.
  exists (
    select 1 from public.transactions ot
    where ot.id = s.transaction_id and ot.is_opening
  )
from public.settlements s;

comment on view public.activity_feed is
  'Chronological union of transactions and settlements, carrying conversion provenance, the transfer a row is one leg of (0020), and — since 0022 — opening_scope: true for every row that belongs to the opening book, transaction or settlement.';

create view public.activity_entries
with (security_invoker = true) as
select
  a.*,
  coalesce(pe.ledger_currency, pe.currency, public.owner_base_currency(a.owner_id))
                                                          as ledger_currency,
  coalesce(a.entered_amount_minor, a.amount_minor)         as entry_amount_minor,
  coalesce(
    a.entered_currency,
    pe.ledger_currency, pe.currency, public.owner_base_currency(a.owner_id)
  )                                                        as entry_currency,
  public.owner_base_currency(a.owner_id)                   as base_currency,
  public.convert_for_owner(
    a.owner_id,
    a.amount_minor,
    coalesce(pe.ledger_currency, pe.currency, public.owner_base_currency(a.owner_id)),
    public.owner_base_currency(a.owner_id)
  )                                                        as amount_base_minor
from public.activity_feed a
join public.people pe on pe.id = a.person_id;

comment on view public.activity_entries is
  'activity_feed plus the entry-currency resolution: entry_amount_minor/entry_currency are what was actually entered, amount_minor stays the ledger figure, and amount_base_minor is the base-currency equivalent (0017, extended 0020, 0022).';

grant select on public.activity_feed, public.activity_entries to authenticated;
revoke all on public.activity_feed    from anon;
revoke all on public.activity_entries from anon;

-- `person_opening` — the balance row only. Adjustments are activity against it,
-- not a second opening balance, and the headline figure the screen shows is
-- still one number.
create view public.person_opening
with (security_invoker = true) as
select
  a.person_id,
  a.owner_id,
  a.id                                      as transaction_id,
  a.entry_type,
  case when a.entry_type = 'credit' then a.amount_minor else -a.amount_minor end
                                            as signed_minor,
  a.amount_minor,
  a.ledger_currency,
  a.entry_amount_minor,
  a.entry_currency,
  a.amount_base_minor,
  a.base_currency,
  a.entered_amount_minor,
  a.entered_currency,
  a.exchange_rate_e9,
  a.exchange_rate_at,
  a.exchange_rate_source,
  public.rate_is_manual(a.exchange_rate_source) as rate_is_manual,
  a.conversion_mode,
  a.auto_converted_amount_minor,
  a.entry_date,
  a.note,
  a.created_at,
  coalesce(st.settled_minor, 0)::bigint     as settled_minor,
  coalesce(st.remaining_minor, a.amount_minor)::bigint as remaining_minor,
  coalesce(st.status, 'open')               as status
from public.activity_entries a
left join lateral public.transaction_settlement_status(a.person_id) st
       on st.transaction_id = a.id
where a.entry_kind = 'transaction'
  and a.is_opening
  and a.opening_role = 'balance'
  and not a.is_void;

comment on view public.person_opening is
  'The balance row of a person''s opening book: the original figure, its currency, the base equivalent, the rate with its provenance, and how much of it has been settled. Adjustments are not here — they are activity against this (0019, extended 0021, narrowed 0022).';

grant select on public.person_opening to authenticated;
revoke all on public.person_opening from anon;

-- -----------------------------------------------------------------------------
-- 3. `person_balances` — the split
--
-- The opening book's settled halves come from `transaction_settlement_status()`,
-- the same FIFO allocator every screen already reads, so the split agrees with
-- what each row says about itself by construction. There is no second
-- allocator, and there is no stored classification that could drift from it.
--
-- The regular halves are the totals minus the opening ones. That subtraction is
-- what makes the invariant hold for free: whatever the allocator does with a
-- settlement, the two sides still add back to the whole.
--
-- Columns are APPENDED. `owner_summary` selects from this view and CREATE OR
-- REPLACE VIEW permits new columns only at the end.
-- -----------------------------------------------------------------------------

create or replace view public.person_balances
with (security_invoker = true) as
select
  p.id                              as person_id,
  p.owner_id,
  p.name,
  p.type,
  p.phone,
  p.email,
  p.is_archived,
  coalesce(p.ledger_currency, p.currency, public.owner_base_currency(p.owner_id)) as currency,
  coalesce(p.currency, public.owner_base_currency(p.owner_id))                    as default_currency,
  public.owner_base_currency(p.owner_id)                                          as base_currency,
  coalesce(t.total_credit, 0)::bigint                                as total_credit,
  coalesce(t.total_debit, 0)::bigint                                 as total_debit,
  coalesce(s.settled_in, 0)::bigint                                  as settled_in,
  coalesce(s.settled_out, 0)::bigint                                 as settled_out,
  (coalesce(s.settled_in, 0) + coalesce(s.settled_out, 0))::bigint   as total_settled,
  (coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))::bigint  as outstanding_receivable,
  (coalesce(t.total_debit, 0)  - coalesce(s.settled_out, 0))::bigint as outstanding_payable,
  ((coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))
    - (coalesce(t.total_debit, 0) - coalesce(s.settled_out, 0)))::bigint as net_balance,
  public.convert_for_owner(
    p.owner_id,
    ((coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))
      - (coalesce(t.total_debit, 0) - coalesce(s.settled_out, 0)))::bigint,
    coalesce(p.ledger_currency, p.currency, public.owner_base_currency(p.owner_id)),
    public.owner_base_currency(p.owner_id)
  )                                                                  as net_balance_base,
  public.convert_for_owner(
    p.owner_id,
    ((coalesce(t.total_credit, 0) - coalesce(s.settled_in, 0))
      - (coalesce(t.total_debit, 0) - coalesce(s.settled_out, 0)))::bigint,
    coalesce(p.ledger_currency, p.currency, public.owner_base_currency(p.owner_id)),
    coalesce(p.currency, public.owner_base_currency(p.owner_id))
  )                                                                  as net_balance_default,
  coalesce(t.txn_count, 0)::bigint                                   as transaction_count,
  coalesce(o.opening_minor, 0)::bigint                               as opening_minor,
  greatest(t.last_activity_at, s.last_activity_at)                   as last_activity_at,

  -- ---- the opening book -----------------------------------------------------
  coalesce(ob.opening_credit, 0)::bigint                             as opening_credit_minor,
  coalesce(ob.opening_debit, 0)::bigint                              as opening_debit_minor,
  coalesce(ob.opening_settled_in, 0)::bigint                         as opening_settled_in,
  coalesce(ob.opening_settled_out, 0)::bigint                        as opening_settled_out,
  (coalesce(ob.opening_settled_in, 0) + coalesce(ob.opening_settled_out, 0))::bigint
                                                                     as opening_settled_total,
  (coalesce(ob.opening_credit, 0) - coalesce(ob.opening_settled_in, 0))::bigint
                                                                     as opening_receivable,
  (coalesce(ob.opening_debit, 0) - coalesce(ob.opening_settled_out, 0))::bigint
                                                                     as opening_payable,
  ((coalesce(ob.opening_credit, 0) - coalesce(ob.opening_settled_in, 0))
    - (coalesce(ob.opening_debit, 0) - coalesce(ob.opening_settled_out, 0)))::bigint
                                                                     as opening_net_minor,
  public.convert_for_owner(
    p.owner_id,
    ((coalesce(ob.opening_credit, 0) - coalesce(ob.opening_settled_in, 0))
      - (coalesce(ob.opening_debit, 0) - coalesce(ob.opening_settled_out, 0)))::bigint,
    coalesce(p.ledger_currency, p.currency, public.owner_base_currency(p.owner_id)),
    public.owner_base_currency(p.owner_id)
  )                                                                  as opening_net_base,
  coalesce(ob.opening_count, 0)::bigint                              as opening_entry_count,

  -- ---- cash in hand: everything that is not the opening book ----------------
  (coalesce(t.total_credit, 0) - coalesce(ob.opening_credit, 0))::bigint
                                                                     as regular_credit_minor,
  (coalesce(t.total_debit, 0) - coalesce(ob.opening_debit, 0))::bigint
                                                                     as regular_debit_minor,
  (coalesce(s.settled_in, 0) - coalesce(ob.opening_settled_in, 0))::bigint
                                                                     as regular_settled_in,
  (coalesce(s.settled_out, 0) - coalesce(ob.opening_settled_out, 0))::bigint
                                                                     as regular_settled_out,
  ((coalesce(s.settled_in, 0) - coalesce(ob.opening_settled_in, 0))
    + (coalesce(s.settled_out, 0) - coalesce(ob.opening_settled_out, 0)))::bigint
                                                                     as regular_settled_total,
  ((coalesce(t.total_credit, 0) - coalesce(ob.opening_credit, 0))
    - (coalesce(s.settled_in, 0) - coalesce(ob.opening_settled_in, 0)))::bigint
                                                                     as regular_receivable,
  ((coalesce(t.total_debit, 0) - coalesce(ob.opening_debit, 0))
    - (coalesce(s.settled_out, 0) - coalesce(ob.opening_settled_out, 0)))::bigint
                                                                     as regular_payable,
  (((coalesce(t.total_credit, 0) - coalesce(ob.opening_credit, 0))
     - (coalesce(s.settled_in, 0) - coalesce(ob.opening_settled_in, 0)))
   - ((coalesce(t.total_debit, 0) - coalesce(ob.opening_debit, 0))
     - (coalesce(s.settled_out, 0) - coalesce(ob.opening_settled_out, 0))))::bigint
                                                                     as cash_in_hand_minor,
  public.convert_for_owner(
    p.owner_id,
    (((coalesce(t.total_credit, 0) - coalesce(ob.opening_credit, 0))
       - (coalesce(s.settled_in, 0) - coalesce(ob.opening_settled_in, 0)))
     - ((coalesce(t.total_debit, 0) - coalesce(ob.opening_debit, 0))
       - (coalesce(s.settled_out, 0) - coalesce(ob.opening_settled_out, 0))))::bigint,
    coalesce(p.ledger_currency, p.currency, public.owner_base_currency(p.owner_id)),
    public.owner_base_currency(p.owner_id)
  )                                                                  as cash_in_hand_base
from public.people p
left join lateral (
  select
    sum(tr.amount_minor) filter (where tr.type = 'credit') as total_credit,
    sum(tr.amount_minor) filter (where tr.type = 'debit')  as total_debit,
    count(*)                                               as txn_count,
    max(tr.transaction_date)                               as last_activity_at
  from public.transactions tr
  where tr.person_id = p.id
    and not tr.is_void
) t on true
left join lateral (
  select
    sum(se.amount_minor) filter (where se.direction = 'in')  as settled_in,
    sum(se.amount_minor) filter (where se.direction = 'out') as settled_out,
    max(se.settlement_date)                                  as last_activity_at
  from public.settlements se
  where se.person_id = p.id
    and not se.is_void
) s on true
left join lateral (
  select sum(case when op.type = 'credit' then op.amount_minor else -op.amount_minor end) as opening_minor
  from public.transactions op
  where op.person_id = p.id and op.is_opening and not op.is_void
) o on true
-- The opening book, settlement included, straight from the allocator.
left join lateral (
  select
    sum(ot.amount_minor)  filter (where ot.type = 'credit') as opening_credit,
    sum(ot.amount_minor)  filter (where ot.type = 'debit')  as opening_debit,
    sum(ost.settled_minor) filter (where ot.type = 'credit') as opening_settled_in,
    sum(ost.settled_minor) filter (where ot.type = 'debit')  as opening_settled_out,
    count(*)                                                as opening_count
  from public.transactions ot
  join public.transaction_settlement_status(p.id) ost on ost.transaction_id = ot.id
  where ot.person_id = p.id and ot.is_opening and not ot.is_void
) ob on true;

comment on view public.person_balances is
  'Authoritative per-person accounting position, denominated in that person''s ledger currency. '
  'Since 0022 it is served in two halves that add back to the whole: cash_in_hand_minor is the '
  'regular trading position and opening_net_minor is the opening book''s, and '
  'cash_in_hand_minor + opening_net_minor = net_balance always.';

-- -----------------------------------------------------------------------------
-- 4. `owner_summary` — the same split, one workspace up
--
-- Receivable and payable are decided per person and then summed, exactly as
-- total_receivable/total_payable already are: a workspace is owed what the
-- people in credit owe it, not the net of everybody.
-- -----------------------------------------------------------------------------

create or replace view public.owner_summary
with (security_invoker = true) as
select
  pb.owner_id,
  max(pb.base_currency)                                                            as base_currency,
  coalesce(sum(pb.net_balance_base) filter (where pb.net_balance_base > 0), 0)::bigint  as total_receivable,
  coalesce(-sum(pb.net_balance_base) filter (where pb.net_balance_base < 0), 0)::bigint as total_payable,
  coalesce(sum(pb.net_balance_base), 0)::bigint                                    as net_position,
  count(*) filter (where coalesce(pb.net_balance_base, pb.net_balance) <> 0)::bigint as people_with_balance,
  count(*)::bigint                                                                 as people_count,
  count(*) filter (where pb.net_balance <> 0 and pb.net_balance_base is null)::bigint as unconverted_people,
  count(distinct pb.currency)::bigint                                              as currency_count,
  coalesce(sum(public.convert_for_owner(pb.owner_id, pb.total_credit,  pb.currency, pb.base_currency)), 0)::bigint as gross_credit,
  coalesce(sum(public.convert_for_owner(pb.owner_id, pb.total_debit,   pb.currency, pb.base_currency)), 0)::bigint as gross_debit,
  coalesce(sum(public.convert_for_owner(pb.owner_id, pb.total_settled, pb.currency, pb.base_currency)), 0)::bigint as gross_settled,

  -- ---- cash in hand ---------------------------------------------------------
  coalesce(sum(pb.cash_in_hand_base), 0)::bigint                                   as cash_in_hand,
  coalesce(sum(pb.cash_in_hand_base) filter (where pb.cash_in_hand_base > 0), 0)::bigint  as cash_receivable,
  coalesce(-sum(pb.cash_in_hand_base) filter (where pb.cash_in_hand_base < 0), 0)::bigint as cash_payable,
  coalesce(sum(public.convert_for_owner(pb.owner_id, pb.regular_settled_total, pb.currency, pb.base_currency)), 0)::bigint as cash_settled,
  count(*) filter (where coalesce(pb.cash_in_hand_base, pb.cash_in_hand_minor) <> 0)::bigint as people_with_cash,

  -- ---- the opening book -----------------------------------------------------
  coalesce(sum(pb.opening_net_base), 0)::bigint                                    as opening_position,
  coalesce(sum(pb.opening_net_base) filter (where pb.opening_net_base > 0), 0)::bigint  as opening_receivable,
  coalesce(-sum(pb.opening_net_base) filter (where pb.opening_net_base < 0), 0)::bigint as opening_payable,
  coalesce(sum(public.convert_for_owner(pb.owner_id, pb.opening_settled_total, pb.currency, pb.base_currency)), 0)::bigint as opening_settled,
  count(*) filter (where pb.opening_entry_count > 0)::bigint                       as people_with_opening
from public.person_balances pb
where not pb.is_archived
group by pb.owner_id;

comment on view public.owner_summary is
  'Dashboard headline numbers for the calling user, converted to the base currency. '
  'Archived people are excluded; people with no usable rate are counted in unconverted_people. '
  'Since 0022, cash_in_hand and opening_position are reported separately and sum to net_position.';

grant select on public.person_balances, public.owner_summary to authenticated;
revoke all on public.person_balances from anon;
revoke all on public.owner_summary   from anon;

-- -----------------------------------------------------------------------------
-- 5. `dashboard()` — "Cash in hand" and "Opening balance" as two totals
--
-- 0020's function with two objects added and one narrowed. `summary` keeps
-- every key it had, so nothing that reads it needs to change; `today` keeps its
-- meaning (all activity), and `cash_in_hand.today` is the same figure with the
-- opening book taken out.
-- -----------------------------------------------------------------------------

create or replace function public.dashboard(
  p_activity_limit int default 10,
  p_people_limit   int default 8
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.current_owner();
  v_base  text;
  v_sum   jsonb;
  v_result jsonb;
begin
  if v_owner is null then
    raise exception 'Not authorised.' using errcode = 'insufficient_privilege';
  end if;

  v_base := public.owner_base_currency(v_owner);
  p_activity_limit := least(greatest(coalesce(p_activity_limit, 10), 1), 50);
  p_people_limit   := least(greatest(coalesce(p_people_limit, 8), 1), 50);

  select coalesce(
    (select to_jsonb(s) from public.owner_summary s where s.owner_id = v_owner),
    jsonb_build_object(
      'owner_id', v_owner, 'base_currency', v_base,
      'total_receivable', 0, 'total_payable', 0, 'net_position', 0,
      'people_with_balance', 0, 'people_count', 0, 'unconverted_people', 0,
      'currency_count', 0,
      'gross_credit', 0, 'gross_debit', 0, 'gross_settled', 0,
      'cash_in_hand', 0, 'cash_receivable', 0, 'cash_payable', 0,
      'cash_settled', 0, 'people_with_cash', 0,
      'opening_position', 0, 'opening_receivable', 0, 'opening_payable', 0,
      'opening_settled', 0, 'people_with_opening', 0
    )
  ) into v_sum;

  select jsonb_build_object(
    'profile', (
      select to_jsonb(x) from (
        select p.id, p.name, p.email, p.phone, p.business_name, p.avatar_url, p.currency
        from public.profiles p where p.id = v_owner
      ) x
    ),
    'base_currency', v_base,
    'summary', v_sum,

    -- The regular trading position. Never contains the opening book.
    'cash_in_hand', jsonb_build_object(
      'base_currency', v_base,
      'position',   (v_sum->>'cash_in_hand')::bigint,
      'receivable', (v_sum->>'cash_receivable')::bigint,
      'payable',    (v_sum->>'cash_payable')::bigint,
      'settled',    (v_sum->>'cash_settled')::bigint,
      'people_count', (v_sum->>'people_with_cash')::bigint,
      'today', (
        select coalesce(sum(a.amount_base_minor), 0)::bigint
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
          and not a.opening_scope
          and a.entry_date = current_date
      ),
      'today_count', (
        select count(*)::bigint
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
          and not a.opening_scope
          and a.entry_date = current_date
      )
    ),

    -- The opening book, on its own. Shown beside cash in hand, never inside it.
    'opening', jsonb_build_object(
      'base_currency', v_base,
      'position',   (v_sum->>'opening_position')::bigint,
      'receivable', (v_sum->>'opening_receivable')::bigint,
      'payable',    (v_sum->>'opening_payable')::bigint,
      'settled',    (v_sum->>'opening_settled')::bigint,
      'people_count', (v_sum->>'people_with_opening')::bigint,
      'today', (
        select coalesce(sum(a.amount_base_minor), 0)::bigint
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
          and a.opening_scope
          and a.entry_date = current_date
      ),
      'today_count', (
        select count(*)::bigint
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
          and a.opening_scope
          and a.entry_date = current_date
      )
    ),

    'today', (
      select jsonb_build_object(
        'credit',  coalesce(sum(a.amount_base_minor)
                     filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0)::bigint,
        'debit',   coalesce(sum(a.amount_base_minor)
                     filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)::bigint,
        'settled', coalesce(sum(a.amount_base_minor)
                     filter (where a.entry_kind = 'settlement'), 0)::bigint,
        'count',   count(*)::bigint
      )
      from public.activity_entries a
      where a.owner_id = v_owner and not a.is_void and a.entry_date = current_date
    ),
    'today_by_currency', coalesce((
      select jsonb_agg(to_jsonb(r) order by (r.currency = v_base) desc, r.currency)
      from (
        select a.entry_currency as currency,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0)::bigint as credit,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)::bigint  as debit,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'settlement'), 0)::bigint                              as settled,
               count(*)::bigint                                                                      as count,
               v_base                                                                                as base_currency,
               public.convert_for_owner(v_owner, coalesce(sum(a.entry_amount_minor), 0)::bigint,
                                        a.entry_currency, v_base)                                    as moved_base_minor
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void and a.entry_date = current_date
        group by a.entry_currency
      ) r
    ), '[]'::jsonb),
    -- Kept, and now split, so a workspace that wants the per-currency breakdown
    -- can still have it and can tell which half each figure belongs to.
    'totals_by_currency', coalesce((
      select jsonb_agg(to_jsonb(r) order by (r.currency = v_base) desc, r.currency)
      from (
        select a.entry_currency as currency,
               v_base as base_currency,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'credit'), 0)::bigint as gross_credit,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'transaction' and a.entry_type = 'debit'), 0)::bigint  as gross_debit,
               coalesce(sum(a.entry_amount_minor)
                 filter (where a.entry_kind = 'settlement'), 0)::bigint                              as gross_settled,
               count(*) filter (where a.entry_kind = 'transaction')::bigint                          as entry_count,
               count(distinct a.person_id)::bigint                                                   as people_count,
               public.convert_for_owner(
                 v_owner,
                 (coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='credit'), 0)
                  - coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='debit'), 0))::bigint,
                 a.entry_currency, v_base)                                                           as net_base_minor,
               (coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='credit'), 0)
                - coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='debit'), 0))::bigint as net_position,
               -- The same row, with the opening book taken out.
               (coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='credit' and not a.opening_scope), 0)
                - coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='debit' and not a.opening_scope), 0))::bigint as cash_net_position,
               (coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='credit' and a.opening_scope), 0)
                - coalesce(sum(a.entry_amount_minor) filter (where a.entry_kind='transaction' and a.entry_type='debit' and a.opening_scope), 0))::bigint as opening_net_position
        from public.activity_entries a
        where a.owner_id = v_owner and not a.is_void
        group by a.entry_currency
      ) r
    ), '[]'::jsonb),
    'recent_activity', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.person_id, pe.name as person_name, a.entry_kind, a.entry_type,
               a.amount_minor, a.entry_date, a.note, a.created_at, a.is_opening,
               a.opening_role, a.opening_scope,
               a.ledger_currency as currency,
               a.entry_amount_minor, a.entry_currency,
               a.amount_base_minor, a.base_currency,
               a.entered_amount_minor, a.entered_currency, a.exchange_rate_e9,
               a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.transfer_id, a.transfer_role, a.transfer_counterparty_id,
               cp.name as transfer_counterparty_name
        from public.activity_entries a
        join public.people pe on pe.id = a.person_id
        left join public.people cp on cp.id = a.transfer_counterparty_id
        where a.owner_id = v_owner and not a.is_void
        order by a.entry_date desc, a.created_at desc
        limit p_activity_limit
      ) r
    ), '[]'::jsonb),
    'people_with_balance', coalesce((
      select jsonb_agg(to_jsonb(r) order by abs(coalesce(r.net_balance_base, r.net_balance)) desc)
      from (
        select pb.person_id, pb.name, pb.type, pb.net_balance, pb.net_balance_base,
               pb.currency, pb.default_currency, pb.base_currency,
               pb.outstanding_receivable, pb.outstanding_payable, pb.last_activity_at,
               pb.cash_in_hand_minor, pb.cash_in_hand_base,
               pb.opening_net_minor, pb.opening_net_base
        from public.person_balances pb
        where pb.owner_id = v_owner and not pb.is_archived and pb.net_balance <> 0
        order by abs(coalesce(pb.net_balance_base, pb.net_balance)) desc
        limit p_people_limit
      ) r
    ), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.dashboard(int, int) from public, anon;
grant execute on function public.dashboard(int, int) to authenticated;

-- -----------------------------------------------------------------------------
-- 6. `person_page()` — the parse bug, and the third section
--
--   * `opening_history` now carries `transaction_id`, `signed_minor` and the
--     settlement columns, so it has the SAME shape as `opening`. That is the
--     fix for "That account could not be loaded.": one payload shape, one
--     model, no key that exists in one and not the other.
--
--   * `opening_activity` is new — the adjustments made to the opening book and
--     the settlements against it, newest first.
--
--   * `timeline` and `timeline_total` exclude everything in the opening book,
--     settlements included. Before this, settling an opening balance put a row
--     among the regular transactions.
--
--   * `regular` and `opening_position` state the two halves outright, so no
--     client has to subtract anything to draw the two figures.
-- -----------------------------------------------------------------------------

create or replace function public.person_page(
  p_person_id uuid,
  p_limit     int default 30,
  p_offset    int default 0
)
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  v_owner uuid := public.assert_caller();
  v_bal   jsonb;
begin
  p_limit  := least(greatest(coalesce(p_limit, 30), 1), 100);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  select to_jsonb(b) into v_bal
  from public.person_balances b
  where b.person_id = p_person_id and b.owner_id = v_owner;

  if v_bal is null then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  return jsonb_build_object(
    'person', (select to_jsonb(p) from public.people p
               where p.id = p_person_id and p.owner_id = v_owner),
    'balance', v_bal,
    'currency', public.person_ledger_currency(p_person_id),
    'default_currency', public.person_currency(p_person_id),
    'base_currency', public.owner_base_currency(v_owner),

    'opening', (
      select to_jsonb(o) from public.person_opening o
      where o.person_id = p_person_id and o.owner_id = v_owner
    ),

    -- The two figures the screen shows side by side, stated by the database so
    -- that no client computes either of them.
    'regular', jsonb_build_object(
      'currency',    v_bal->>'currency',
      'base_currency', v_bal->>'base_currency',
      'position',    (v_bal->>'cash_in_hand_minor')::bigint,
      'position_base', nullif(v_bal->>'cash_in_hand_base', '')::bigint,
      'receivable',  (v_bal->>'regular_receivable')::bigint,
      'payable',     (v_bal->>'regular_payable')::bigint,
      'settled',     (v_bal->>'regular_settled_total')::bigint,
      'credit',      (v_bal->>'regular_credit_minor')::bigint,
      'debit',       (v_bal->>'regular_debit_minor')::bigint
    ),
    'opening_position', jsonb_build_object(
      'currency',    v_bal->>'currency',
      'base_currency', v_bal->>'base_currency',
      'position',    (v_bal->>'opening_net_minor')::bigint,
      'position_base', nullif(v_bal->>'opening_net_base', '')::bigint,
      'receivable',  (v_bal->>'opening_receivable')::bigint,
      'payable',     (v_bal->>'opening_payable')::bigint,
      'settled',     (v_bal->>'opening_settled_total')::bigint,
      'credit',      (v_bal->>'opening_credit_minor')::bigint,
      'debit',       (v_bal->>'opening_debit_minor')::bigint,
      'entry_count', (v_bal->>'opening_entry_count')::bigint
    ),

    -- Opening balances that were replaced. Same shape as `opening`, which is
    -- the whole point: one payload, one model, one parse.
    'opening_history', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from (
        select a.person_id,
               a.owner_id,
               a.id                    as transaction_id,
               a.id,
               a.amount_minor,
               case when a.entry_type = 'credit' then a.amount_minor else -a.amount_minor end
                                       as signed_minor,
               a.entry_type, a.entry_date, a.created_at,
               a.entry_amount_minor, a.entry_currency, a.ledger_currency,
               a.amount_base_minor, a.base_currency,
               a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               public.rate_is_manual(a.exchange_rate_source) as rate_is_manual,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.note,
               a.opening_role,
               0::bigint               as settled_minor,
               0::bigint               as remaining_minor,
               'void'::text            as status
        from public.activity_entries a
        where a.owner_id = v_owner and a.person_id = p_person_id
          and a.entry_kind = 'transaction' and a.is_opening
          and a.opening_role = 'balance' and a.is_void
        order by a.created_at desc
        limit 20
      ) r
    ), '[]'::jsonb),

    -- What has happened to the opening book since: credits, debits, and its own
    -- settlements. These are NEVER in `timeline`.
    'opening_activity', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.entry_kind, a.entry_type, a.money_direction, a.amount_minor,
               a.entry_date, a.note, a.is_void, a.related_transaction_id, a.created_at,
               a.is_opening, a.opening_role, a.opening_scope,
               a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.entry_amount_minor, a.entry_currency,
               a.ledger_currency, a.amount_base_minor, a.base_currency,
               st.settled_minor, st.remaining_minor, st.status
        from public.activity_entries a
        left join public.transaction_settlement_status(p_person_id) st
               on st.transaction_id = a.id and a.entry_kind = 'transaction'
        where a.owner_id = v_owner and a.person_id = p_person_id
          and a.opening_scope
          and coalesce(a.opening_role, 'adjustment') <> 'balance'
        order by a.entry_date desc, a.created_at desc
        limit 100
      ) r
    ), '[]'::jsonb),

    -- Regular activity only. Nothing in the opening book reaches this list.
    'timeline', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.entry_kind, a.entry_type, a.money_direction, a.amount_minor,
               a.entry_date, a.note, a.is_void, a.related_transaction_id, a.created_at,
               a.is_opening, a.opening_role, a.opening_scope,
               a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.entry_amount_minor, a.entry_currency,
               a.ledger_currency, a.amount_base_minor, a.base_currency,
               a.transfer_id, a.transfer_role, a.transfer_counterparty_id,
               cp.name as transfer_counterparty_name,
               st.settled_minor, st.remaining_minor, st.status
        from public.activity_entries a
        left join public.transaction_settlement_status(p_person_id) st
               on st.transaction_id = a.id and a.entry_kind = 'transaction'
        left join public.people cp on cp.id = a.transfer_counterparty_id
        where a.owner_id = v_owner and a.person_id = p_person_id
          and not a.opening_scope
        order by a.entry_date desc, a.created_at desc
        limit p_limit offset p_offset
      ) r
    ), '[]'::jsonb),

    'timeline_total', (
      select count(*) from public.activity_feed a
      where a.owner_id = v_owner and a.person_id = p_person_id
        and not a.opening_scope
    ),

    'open_transactions', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.transaction_date, r.created_at)
      from (
        select t.id, t.type, t.amount_minor, t.transaction_date, t.description,
               t.created_at, t.is_opening, st.remaining_minor, st.settled_minor
        from public.transactions t
        join public.transaction_settlement_status(p_person_id) st on st.transaction_id = t.id
        where t.owner_id = v_owner and t.person_id = p_person_id
          and not t.is_void and not t.is_opening and t.transfer_id is null
          and st.remaining_minor > 0
        order by t.transaction_date, t.created_at
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.person_page(uuid, int, int) to authenticated;

comment on function public.person_page(uuid, int, int) is
  'One person''s whole screen in sections. `regular` is the cash-in-hand position and `timeline` the activity behind it; `opening`, `opening_position` and `opening_activity` are the opening book, and never appear in either. `balance` still includes both, and regular.position + opening_position.position = balance.net_balance (0022).';

-- -----------------------------------------------------------------------------
-- 7. `adjust_opening_balance()` — credit and debit against the opening book
--
-- The direction model is the one the rest of the ledger uses and no other:
-- `p_type` is the stored `txn_type`, `credit` is receivable and `debit` is
-- payable, exactly as `create_transaction()` takes it, and the clients map the
-- spoken words onto it through the single mapping in direction.ts /
-- direction.dart. Nothing new is invented here.
--
-- The row it writes is an ordinary transaction in every respect except that it
-- carries `is_opening` and `opening_role = 'adjustment'`. That is what keeps it
-- out of `timeline`, out of `open_transactions`, out of cash in hand, and
-- inside the opening book's totals — with no second code path for the
-- arithmetic, which is the same reason 0010 made the opening balance a
-- transaction in the first place.
-- -----------------------------------------------------------------------------

create or replace function public.adjust_opening_balance(
  p_person_id    uuid,
  p_type         public.txn_type,
  p_amount_minor bigint      default null,
  p_date         date        default current_date,
  p_note         text        default null,
  p_entered_amount_minor bigint      default null,
  p_entered_currency     text        default null,
  p_exchange_rate_e9     bigint      default null,
  p_rate_at              timestamptz default null,
  p_rate_source          text        default null,
  p_converted_amount_minor bigint    default null,
  p_conversion_mode      text        default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner    uuid := public.assert_caller();
  v_currency text;
  v_entered  text := upper(nullif(btrim(coalesce(p_entered_currency, '')), ''));
  v_conv     record;
  v_foreign  boolean;
  v_opening  public.transactions;
  v_row      public.transactions;
begin
  v_currency := public.person_ledger_currency(p_person_id);
  if v_currency is null then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  -- An adjustment adjusts something. Without a balance row there is nothing to
  -- adjust, and the right action is to enter an opening balance instead.
  select t.* into v_opening
  from public.transactions t
  where t.person_id = p_person_id
    and t.owner_id  = v_owner
    and t.is_opening
    and t.opening_role = 'balance'
    and not t.is_void
  limit 1;

  if not found then
    raise exception 'This account has no opening balance to adjust.'
      using errcode = 'no_data_found',
            hint    = 'Enter an opening balance on the account first.';
  end if;

  if p_date > current_date + interval '1 day' then
    raise exception 'Transaction date cannot be in the future.' using errcode = 'check_violation';
  end if;

  -- Same conversion path as every other money RPC: the database does the
  -- arithmetic, at the rate it is given, and freezes it on the row.
  v_conv := public.resolve_conversion(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_exchange_rate_e9,
    p_converted_amount_minor, p_conversion_mode
  );
  v_foreign := v_entered is not null and v_entered <> v_currency;

  insert into public.transactions (
    owner_id, person_id, type, amount_minor, transaction_date, description,
    is_opening, opening_role,
    entered_amount_minor, entered_currency, exchange_rate_e9,
    exchange_rate_at, exchange_rate_source,
    conversion_mode, auto_converted_amount_minor, created_by
  )
  values (
    v_owner, p_person_id, p_type, v_conv.o_amount_minor, coalesce(p_date, current_date),
    coalesce(nullif(btrim(coalesce(p_note, '')), ''), 'Opening balance adjustment'),
    true, 'adjustment',
    case when v_foreign then p_entered_amount_minor end,
    case when v_foreign then v_entered end,
    case when v_foreign then p_exchange_rate_e9 end,
    case when v_foreign then coalesce(p_rate_at, now()) end,
    case when v_foreign then left(coalesce(p_rate_source, 'manual'), 60) end,
    v_conv.o_mode,
    v_conv.o_auto_minor,
    auth.uid()
  )
  returning * into v_row;

  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'opening', (select to_jsonb(o) from public.person_opening o where o.person_id = p_person_id),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
  );
end;
$$;

revoke all on function public.adjust_opening_balance(
  uuid, public.txn_type, bigint, date, text, bigint, text, bigint, timestamptz, text, bigint, text
) from public, anon;
grant execute on function public.adjust_opening_balance(
  uuid, public.txn_type, bigint, date, text, bigint, text, bigint, timestamptz, text, bigint, text
) to authenticated;

comment on function public.adjust_opening_balance(
  uuid, public.txn_type, bigint, date, text, bigint, text, bigint, timestamptz, text, bigint, text
) is
  'Records a credit or debit against a person''s opening book. Same direction enum, same conversion path and same engine as an ordinary transaction — it simply is not one, and never appears among them (0022).';

-- -----------------------------------------------------------------------------
-- 8. `settle_opening_balance()` — settles the BOOK, not one row
--
-- 0021's function generalised. With adjustments the opening book can be more
-- than one row, so the direction is derived from the book's NET position and
-- the settlement is targeted, oldest row first, across the rows that make it
-- up. Targeting matters: the FIFO spill in `transaction_settlement_status()` is
-- account-wide, so an untargeted settlement would leak onto regular
-- transactions and move cash in hand — which is exactly what this must not do.
--
-- For an account with no adjustments the behaviour is 0021's, to the digit:
-- one row, one targeted settlement, the amount defaulting to what is left.
-- -----------------------------------------------------------------------------

create or replace function public.settle_opening_balance(
  p_person_id            uuid,
  p_amount_minor         bigint      default null,
  p_date                 date        default current_date,
  p_note                 text        default null,
  p_entered_amount_minor bigint      default null,
  p_entered_currency     text        default null,
  p_exchange_rate_e9     bigint      default null,
  p_rate_at              timestamptz default null,
  p_rate_source          text        default null,
  p_converted_amount_minor bigint    default null,
  p_conversion_mode      text        default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner     uuid := public.assert_caller();
  v_net       bigint;
  v_type      public.txn_type;
  v_direction public.settlement_direction;
  v_remaining bigint;
  v_left      bigint;
  v_take      bigint;
  v_first     boolean := true;
  v_result    jsonb;
  r_row       record;
begin
  if not exists (
    select 1 from public.transactions t
    where t.person_id = p_person_id and t.owner_id = v_owner
      and t.is_opening and not t.is_void
  ) then
    raise exception 'This account has no opening balance to settle.'
      using errcode = 'no_data_found';
  end if;

  -- The book's net position, and therefore which way money must move to
  -- retire it. Derived, never accepted — getting this pair the wrong way round
  -- is the single mistake this function exists to make impossible.
  select b.opening_net_minor into v_net
  from public.person_balances b
  where b.person_id = p_person_id and b.owner_id = v_owner;

  if coalesce(v_net, 0) = 0 then
    raise exception 'This opening balance is already settled in full.'
      using errcode = 'check_violation';
  end if;

  if v_net > 0 then
    v_type      := 'credit';
    v_direction := 'in';
  else
    v_type      := 'debit';
    v_direction := 'out';
  end if;

  v_remaining := abs(v_net);

  -- Default to closing it, which is the common case.
  v_left := coalesce(p_amount_minor, p_entered_amount_minor, v_remaining);
  if p_entered_amount_minor is not null and p_amount_minor is null then
    -- A foreign-currency settlement states its own ledger figure through the
    -- conversion arguments; create_settlement() resolves it. Allocate against
    -- the whole remainder in that case rather than guessing a ledger amount.
    v_left := v_remaining;
  end if;

  if v_left > v_remaining then
    raise exception 'That is more than is left of this opening balance.'
      using errcode = 'check_violation';
  end if;

  -- The exemption, for this account and this statement only.
  perform set_config('accounic.settle_opening', p_person_id::text, true);

  for r_row in
    select t.id, st.remaining_minor
    from public.transactions t
    join public.transaction_settlement_status(p_person_id) st on st.transaction_id = t.id
    where t.person_id = p_person_id and t.owner_id = v_owner
      and t.is_opening and not t.is_void and t.type = v_type
      and st.remaining_minor > 0
    order by t.transaction_date, t.created_at, t.id
  loop
    exit when v_left <= 0;
    v_take := least(v_left, r_row.remaining_minor);

    v_result := public.create_settlement(
      p_person_id      => p_person_id,
      p_amount_minor   => v_take,
      p_direction      => v_direction,
      p_transaction_id => r_row.id,
      p_date           => coalesce(p_date, current_date),
      p_note           => p_note,
      -- The entered figure and its rate describe the WHOLE payment; they are
      -- carried on the first row so the provenance is recorded once and the
      -- ledger figures still add up.
      p_entered_amount_minor   => case when v_first then p_entered_amount_minor end,
      p_entered_currency       => case when v_first then p_entered_currency end,
      p_exchange_rate_e9       => case when v_first then p_exchange_rate_e9 end,
      p_rate_at                => case when v_first then p_rate_at end,
      p_rate_source            => case when v_first then p_rate_source end,
      p_converted_amount_minor => case when v_first then p_converted_amount_minor end,
      p_conversion_mode        => case when v_first then p_conversion_mode end
    );

    v_left  := v_left - v_take;
    v_first := false;
  end loop;

  perform set_config('accounic.settle_opening', '', true);

  return jsonb_build_object(
    'settlement', v_result->'settlement',
    'opening', (select to_jsonb(o) from public.person_opening o where o.person_id = p_person_id),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
  );
end;
$$;

revoke all on function public.settle_opening_balance(
  uuid, bigint, date, text, bigint, text, bigint, timestamptz, text, bigint, text
) from public, anon;
grant execute on function public.settle_opening_balance(
  uuid, bigint, date, text, bigint, text, bigint, timestamptz, text, bigint, text
) to authenticated;

comment on function public.settle_opening_balance(
  uuid, bigint, date, text, bigint, text, bigint, timestamptz, text, bigint, text
) is
  'Settles a person''s opening book, and only that: the direction comes from the book''s net position and the settlement is targeted at the opening rows so it can never spill onto a regular transaction. The one route by which a settlement may name an opening balance (0021, generalised 0022).';

-- -----------------------------------------------------------------------------
-- 9. `set_person_opening_balance()` — replace the BALANCE row, leave the
--    adjustments alone
--
-- 0014's function with one clause changed: the row it retracts is the balance
-- row, not "any opening row". An adjustment is a separate movement of money and
-- retracting it silently because the carried-in figure was corrected would
-- destroy a record the user made deliberately.
-- -----------------------------------------------------------------------------

create or replace function public.set_person_opening_balance(
  p_person_id            uuid,
  p_direction            text,
  p_amount_minor         bigint      default null,
  p_date                 date        default null,
  p_entered_amount_minor bigint      default null,
  p_entered_currency     text        default null,
  p_rate_e9              bigint      default null,
  p_rate_at              timestamptz default null,
  p_rate_source          text        default null,
  p_converted_amount_minor bigint    default null,
  p_conversion_mode      text        default null
)
returns jsonb
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_owner    uuid := public.assert_caller();
  v_person   public.people;
  v_currency text;
  v_entered  text := upper(nullif(btrim(coalesce(p_entered_currency, '')), ''));
  v_type     public.txn_type;
  v_conv     record;
  v_foreign  boolean;
  v_existing uuid;
  v_row      public.transactions;
begin
  select * into v_person
  from public.people p
  where p.id = p_person_id and p.owner_id = v_owner;

  if not found then
    raise exception 'Person not found.' using errcode = 'no_data_found';
  end if;

  v_currency := coalesce(v_person.ledger_currency, v_person.currency,
                         public.owner_base_currency(v_owner));

  -- Replacing an opening balance retracts the old one rather than editing it,
  -- so the correction is visible in the history. Adjustments are untouched.
  select t.id into v_existing
  from public.transactions t
  where t.person_id = p_person_id and t.owner_id = v_owner
    and t.is_opening and t.opening_role = 'balance' and not t.is_void
  limit 1;

  if v_existing is not null then
    update public.transactions
      set is_void = true, void_reason = 'Opening balance replaced'
    where id = v_existing;
  end if;

  if coalesce(p_direction, 'none') = 'none'
     or coalesce(p_amount_minor, p_entered_amount_minor, 0) <= 0 then
    return jsonb_build_object(
      'transaction', null,
      'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
    );
  end if;

  v_type := case p_direction
              when 'they_owe_me' then 'credit'::public.txn_type
              when 'i_owe_them'  then 'debit'::public.txn_type
              else null
            end;

  if v_type is null then
    raise exception 'Say who owes whom before entering an opening balance.'
      using errcode = 'check_violation';
  end if;

  v_conv := public.resolve_conversion(
    v_currency, p_amount_minor, p_entered_amount_minor, v_entered, p_rate_e9,
    p_converted_amount_minor, p_conversion_mode
  );
  v_foreign := v_entered is not null and v_entered <> v_currency;

  insert into public.transactions (
    owner_id, person_id, type, amount_minor, transaction_date, description,
    is_opening, opening_role, entered_amount_minor, entered_currency,
    exchange_rate_e9, exchange_rate_at, exchange_rate_source,
    conversion_mode, auto_converted_amount_minor, created_by
  )
  values (
    v_owner, p_person_id, v_type, v_conv.o_amount_minor,
    coalesce(p_date, v_person.created_at::date, current_date),
    'Opening balance',
    true, 'balance',
    case when v_foreign then p_entered_amount_minor end,
    case when v_foreign then v_entered end,
    case when v_foreign then p_rate_e9 end,
    case when v_foreign then coalesce(p_rate_at, now()) end,
    case when v_foreign then left(coalesce(p_rate_source, 'manual'), 60) end,
    v_conv.o_mode,
    v_conv.o_auto_minor,
    auth.uid()
  )
  returning * into v_row;

  return jsonb_build_object(
    'transaction', to_jsonb(v_row),
    'opening', (select to_jsonb(o) from public.person_opening o where o.person_id = p_person_id),
    'balance', (select to_jsonb(b) from public.person_balances b where b.person_id = p_person_id)
  );
end;
$$;

grant execute on function public.set_person_opening_balance(
  uuid, text, bigint, date, bigint, text, bigint, timestamptz, text, bigint, text
) to authenticated;

-- -----------------------------------------------------------------------------
-- 10. The invariant, checked against the data that exists right now
--
-- Not a test — a migration-time assertion. If the split ever failed to add back
-- to the position the engine already reported, this file would be wrong about
-- money, and it says so instead of shipping quietly.
-- -----------------------------------------------------------------------------

do $$
declare
  v_bad bigint;
begin
  select count(*) into v_bad
  from public.person_balances b
  where b.cash_in_hand_minor + b.opening_net_minor <> b.net_balance;

  if v_bad > 0 then
    raise exception
      '0022: % account(s) where cash_in_hand + opening_net <> net_balance. The split is wrong; refusing to install it.',
      v_bad;
  end if;

  raise notice
    '0022 §10: cash_in_hand + opening_net = net_balance holds for every account. Nothing was rewritten.';
end $$;
