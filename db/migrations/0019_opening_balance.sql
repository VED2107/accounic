-- =============================================================================
-- 0019 — the opening balance stops being a transaction on the timeline
--
-- WHAT WAS WRONG
--
-- Since 0010 an opening balance has been a transaction carrying `is_opening`.
-- That was the right *storage* decision and it stays: the balance engine then
-- computes the position correctly by construction, with no second code path and
-- no second place for the arithmetic to drift.
--
-- It was the wrong *presentation* decision. `person_page()` served the opening
-- row inside `timeline`, beside the credits and debits, and listed it in
-- `open_transactions` — so a balance carried in from before the account existed
-- showed up as something that happened on a Tuesday, wore a Credit or Debit
-- label, and offered a "Settle this" button. A user could settle their own
-- opening balance as though somebody had paid it.
--
-- WHAT THIS CHANGES
--
--   1. `person_opening` — one view that answers "what did this account open
--      with, in what currency, at what rate, and what is that worth in base?".
--      One row per person that has one; no row for a person that does not.
--
--   2. `person_page()` returns `opening` (the current opening balance, or null)
--      and `opening_history` (superseded ones, kept because replacing an
--      opening balance retracts the old rather than editing it). `timeline`
--      no longer carries opening rows at all, and `timeline_total` counts what
--      the timeline actually holds.
--
--   3. `open_transactions` excludes opening rows, so no screen can offer
--      "Settle this" against one.
--
--   4. The database refuses a settlement that names an opening balance. The UI
--      change above is a convenience; this is the guarantee.
--
-- WHAT IT DOES NOT CHANGE
--
-- No amount, currency, rate, date or id moves. The opening balance keeps
-- flowing through `person_balances` exactly as before — it is still a
-- transaction, it is still summed into `total_credit` / `total_debit`, and
-- `net_balance` is the same integer after this file as before it. An
-- account-level settlement still retires it along with everything else, which
-- is correct: what is refused is settling it *as an individual transaction*.
--
-- §1 also reclassifies opening balances that predate the flag, and does so
-- idempotently. It creates nothing and rewrites no money.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Historical opening balances, reclassified rather than recreated
--
-- Every opening balance written by this product since 0010 already carries
-- `is_opening`, because `set_person_opening_balance()` and `create_person()`
-- are the only writers and both set it. There is therefore normally nothing to
-- do here, and this block says so out loud rather than assuming it.
--
-- What it does repair is the one shape that can exist without the flag: a plain
-- transaction a user entered by hand, before the feature existed, and described
-- exactly as an opening balance. Those are reclassified — the SAME row, the
-- same amount, the same currency, the same rate, the same date, the same id —
-- and only when every one of these holds:
--
--   * it is not void,
--   * its description is exactly "opening balance", ignoring case and padding,
--   * the person has no non-void opening balance already (so nothing is ever
--     duplicated, and the unique index from 0010 could not permit it anyway),
--   * it is that person's OLDEST transaction, because an "opening balance"
--     recorded after three months of trading is a note, not an opening.
--
-- Idempotent by construction: the second run finds no row that still lacks the
-- flag. Nothing is inserted, no amount is touched, and a row that fails any
-- test is left exactly as it is rather than guessed at.
-- -----------------------------------------------------------------------------

do $$
declare
  v_reclassified bigint := 0;
  v_flagged      bigint;
  v_ambiguous    bigint;
begin
  with candidate as (
    select t.id
    from public.transactions t
    where not t.is_void
      and not t.is_opening
      and lower(btrim(coalesce(t.description, ''))) = 'opening balance'
      -- No opening balance on that account yet.
      and not exists (
        select 1 from public.transactions o
        where o.person_id = t.person_id and o.is_opening and not o.is_void
      )
      -- And it is the earliest thing on the account.
      and not exists (
        select 1 from public.transactions e
        where e.person_id = t.person_id
          and not e.is_void
          and e.id <> t.id
          and (e.transaction_date, e.created_at) < (t.transaction_date, t.created_at)
      )
      -- Exactly one candidate on that account, so "the oldest" is unambiguous.
      and 1 = (
        select count(*) from public.transactions c
        where c.person_id = t.person_id
          and not c.is_void
          and not c.is_opening
          and lower(btrim(coalesce(c.description, ''))) = 'opening balance'
      )
  )
  update public.transactions t
     set is_opening = true
    from candidate c
   where t.id = c.id;
  get diagnostics v_reclassified = row_count;

  select count(*) into v_flagged
  from public.transactions where is_opening and not is_void;

  select count(*) into v_ambiguous
  from public.transactions t
  where not t.is_void
    and not t.is_opening
    and lower(btrim(coalesce(t.description, ''))) = 'opening balance';

  raise notice
    '0019: % opening balance(s) reclassified in place; % now carry the flag; % description-only row(s) left alone as ambiguous. No amount, currency, rate or date was altered.',
    v_reclassified, v_flagged, v_ambiguous;
end $$;

-- -----------------------------------------------------------------------------
-- 2. `person_opening` — the one definition of "this account's opening balance"
--
-- Reads `activity_entries` (0017) so the entered figure, the ledger figure and
-- the base equivalent are all resolved by the same view every other screen
-- uses. Nothing is converted here that is not converted there.
--
-- `signed_minor` is positive when they owe the user, matching
-- `person_balances.opening_minor` to the digit.
-- -----------------------------------------------------------------------------

create or replace view public.person_opening
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
  a.created_at
from public.activity_entries a
where a.entry_kind = 'transaction'
  and a.is_opening
  and not a.is_void;

comment on view public.person_opening is
  'One row per person that has an opening balance: the original figure, its currency, the base equivalent, and the rate with its provenance. Never more than one row per person — 0010''s unique index guarantees it (0019).';

grant select on public.person_opening to authenticated;
revoke all on public.person_opening from anon;

-- -----------------------------------------------------------------------------
-- 3. An opening balance cannot be settled as an individual transaction
--
-- The check runs on INSERT only, and deliberately. Voiding a settlement is an
-- UPDATE of `is_void` on a row that already exists; if a settlement against an
-- opening balance was recorded by an older version of this product, the user
-- must still be able to reverse it. Refusing the reversal would strand exactly
-- the rows this rule exists to discourage.
--
-- Account-level settlement is untouched: it names no transaction, so it does
-- not reach this branch, and it still retires the opening balance along with
-- everything else outstanding. That is right — the opening balance is real
-- money owed. What is refused is pressing "Settle this" on the line that says
-- what the account opened with.
-- -----------------------------------------------------------------------------

create or replace function public.validate_settlement_row()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_txn public.transactions%rowtype;
begin
  if new.transaction_id is not null then
    select * into v_txn
    from public.transactions t
    where t.id = new.transaction_id;

    if not found then
      raise exception 'Referenced transaction does not exist.'
        using errcode = 'foreign_key_violation';
    end if;

    if v_txn.person_id <> new.person_id then
      raise exception 'Settlement and transaction belong to different people.'
        using errcode = 'check_violation';
    end if;

    if v_txn.is_void then
      raise exception 'Cannot settle a voided transaction.'
        using errcode = 'check_violation';
    end if;

    if tg_op = 'INSERT' and v_txn.is_opening then
      raise exception 'An opening balance is not a transaction that can be settled on its own.'
        using errcode = 'check_violation',
              hint    = 'Settle the account instead, or record the payment as a settlement against the whole balance.';
    end if;

    -- credit is settled by money coming in; debit by money going out.
    if (v_txn.type = 'credit' and new.direction <> 'in')
       or (v_txn.type = 'debit' and new.direction <> 'out') then
      raise exception 'Settlement direction does not match the transaction type.'
        using errcode = 'check_violation';
    end if;
  end if;

  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 4. person_page() — two sections instead of one list
--
-- 0018's function with three changes and nothing else:
--
--   * `opening` and `opening_history` added,
--   * `timeline` and `timeline_total` exclude opening rows,
--   * `open_transactions` excludes opening rows.
--
-- `balance` is untouched and still carries `opening_minor`, so the current
-- position continues to include the opening balance exactly as it did.
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

    -- The account's own section. Null when the account has none, which is not
    -- the same as zero and is presented differently.
    'opening', (
      select to_jsonb(o) from public.person_opening o
      where o.person_id = p_person_id and o.owner_id = v_owner
    ),

    -- Opening balances that were replaced. Kept because replacing one retracts
    -- the old rather than editing it, and the correction is worth being able to
    -- see. They affect no balance.
    'opening_history', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.created_at desc)
      from (
        select a.id, a.amount_minor, a.entry_type, a.entry_date, a.created_at,
               a.entry_amount_minor, a.entry_currency, a.ledger_currency,
               a.amount_base_minor, a.base_currency,
               a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor
        from public.activity_entries a
        where a.owner_id = v_owner and a.person_id = p_person_id
          and a.entry_kind = 'transaction' and a.is_opening and a.is_void
        order by a.created_at desc
        limit 20
      ) r
    ), '[]'::jsonb),

    -- Regular activity: credits, debits and settlements. No opening balances.
    'timeline', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.entry_date desc, r.created_at desc)
      from (
        select a.id, a.entry_kind, a.entry_type, a.money_direction, a.amount_minor,
               a.entry_date, a.note, a.is_void, a.related_transaction_id, a.created_at,
               a.is_opening, a.entered_amount_minor, a.entered_currency,
               a.exchange_rate_e9, a.exchange_rate_at, a.exchange_rate_source,
               a.conversion_mode, a.auto_converted_amount_minor,
               a.entry_amount_minor, a.entry_currency,
               a.ledger_currency, a.amount_base_minor, a.base_currency,
               st.settled_minor, st.remaining_minor, st.status
        from public.activity_entries a
        left join public.transaction_settlement_status(p_person_id) st
               on st.transaction_id = a.id and a.entry_kind = 'transaction'
        where a.owner_id = v_owner and a.person_id = p_person_id
          and not a.is_opening
        order by a.entry_date desc, a.created_at desc
        limit p_limit offset p_offset
      ) r
    ), '[]'::jsonb),

    'timeline_total', (
      select count(*) from public.activity_feed a
      where a.owner_id = v_owner and a.person_id = p_person_id
        and not a.is_opening
    ),

    -- Never an opening balance: it is not a transaction anyone settles on its
    -- own, and the database refuses it (§3).
    'open_transactions', coalesce((
      select jsonb_agg(to_jsonb(r) order by r.transaction_date, r.created_at)
      from (
        select t.id, t.type, t.amount_minor, t.transaction_date, t.description,
               t.created_at, t.is_opening, st.remaining_minor, st.settled_minor
        from public.transactions t
        join public.transaction_settlement_status(p_person_id) st on st.transaction_id = t.id
        where t.owner_id = v_owner and t.person_id = p_person_id
          and not t.is_void and not t.is_opening and st.remaining_minor > 0
        order by t.transaction_date, t.created_at
      ) r
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.person_page(uuid, int, int) to authenticated;

comment on function public.person_page(uuid, int, int) is
  'One person''s whole screen, in two sections: `opening` is the balance the account was carried in with, `timeline` is the regular activity and never contains it. `balance` still includes the opening balance in every figure (0019).';
