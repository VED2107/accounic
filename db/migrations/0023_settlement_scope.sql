-- =============================================================================
-- 0023 — a settlement spills within its own book, and never across the fence
--
-- WHAT IS WRONG
--
-- `transaction_settlement_status()` allocates a settlement to the transaction
-- it names, and spills whatever is left over the person's other rows, oldest
-- first. That spill is account-wide, and 0022 gave it a way to do real damage:
--
--   1. a user settles an opening balance — the settlement names the opening row;
--   2. the user later corrects the opening balance, which RETRACTS the old row
--      and writes a new one (0011, unchanged);
--   3. the settlement now names a voided row, so the targeted step finds
--      nothing and the whole amount spills;
--   4. the spill is ordered by (transaction_date, created_at, id), and lands on
--      whatever is oldest — frequently an ordinary credit.
--
-- The result: money paid against what an account was carried in with quietly
-- pays off a trading invoice instead, and **cash in hand moves** because an
-- opening balance was edited. 0022 says in as many words that this must not
-- happen; it closed the door for `settle_opening_balance()` by targeting each
-- opening row, and left this one open.
--
-- It is also non-deterministic. Rows written in one transaction share
-- `created_at` to the microsecond, so the tie-break falls to `id` — a random
-- uuid. The same ledger reports different figures on different reads. That is
-- how this was found: `db/tests/11` passed and failed on alternate runs.
--
-- WHAT THIS CHANGES
--
-- One rule, applied to the spill only:
--
--   * a settlement that NAMES AN OPENING ROW spills across opening rows only;
--   * a settlement that NAMES A REGULAR ROW spills across regular rows only;
--   * a settlement that names NOTHING — an account-level settlement — spills
--     across everything, exactly as it always has, because it is a payment
--     against the account as a whole and that is what the user asked for.
--
-- The targeted step is untouched: a settlement still pays down the row it names
-- first. Only where the remainder may land is narrowed, and only for a
-- settlement that named something.
--
-- WHAT IT DOES NOT CHANGE
--
-- No amount, direction, date or id. `person_balances.net_balance`,
-- `total_credit`, `total_debit`, `settled_in`, `settled_out`,
-- `outstanding_receivable` and `outstanding_payable` are sums over rows and
-- never consulted the allocator, so every one of them is the same integer after
-- this file as before it. What changes is which row a spilled settlement is
-- reported against — and therefore that cash in hand stops moving when an
-- opening balance is edited.
-- =============================================================================

create or replace function public.transaction_settlement_status(p_person_id uuid)
returns table (
  transaction_id   uuid,
  amount_minor     bigint,
  settled_minor    bigint,
  remaining_minor  bigint,
  status           text
)
language plpgsql
stable
as $$
declare
  v_dir      public.settlement_direction;
  v_type     public.txn_type;
  v_ids      uuid[];
  v_amounts  bigint[];
  v_opening  boolean[];
  v_rem      bigint[];
  v_n        int;
  v_i        int;
  v_pos      int;
  v_left     bigint;
  v_take     bigint;
  -- null = account-level, so the spill is unrestricted. true/false confine it
  -- to the opening book or to the regular one.
  v_scope    boolean;
  r_settle   record;
begin
  foreach v_dir in array array['in', 'out']::public.settlement_direction[] loop
    v_type := case v_dir when 'in' then 'credit'::public.txn_type
                         else 'debit'::public.txn_type end;

    select array_agg(t.id         order by t.transaction_date, t.created_at, t.id),
           array_agg(t.amount_minor order by t.transaction_date, t.created_at, t.id),
           array_agg(t.is_opening   order by t.transaction_date, t.created_at, t.id)
      into v_ids, v_amounts, v_opening
    from public.transactions t
    where t.person_id = p_person_id
      and t.type = v_type
      and not t.is_void;

    if v_ids is null then
      continue;
    end if;

    v_n   := array_length(v_ids, 1);
    v_rem := v_amounts;

    for r_settle in
      select s.amount_minor, s.transaction_id,
             -- Which book this settlement belongs to, decided by the row it
             -- names. A voided target still decides it: money paid against an
             -- opening balance was paid against an opening balance, whether or
             -- not that row was later retracted. That is the whole fix.
             (select ot.is_opening
                from public.transactions ot
               where ot.id = s.transaction_id) as target_is_opening
      from public.settlements s
      where s.person_id = p_person_id
        and s.direction = v_dir
        and not s.is_void
      order by s.settlement_date, s.created_at, s.id
    loop
      v_left  := r_settle.amount_minor;
      v_scope := r_settle.target_is_opening;

      -- 1. targeted allocation
      if r_settle.transaction_id is not null then
        v_pos := array_position(v_ids, r_settle.transaction_id);
        if v_pos is not null and v_rem[v_pos] > 0 then
          v_take        := least(v_left, v_rem[v_pos]);
          v_rem[v_pos]  := v_rem[v_pos] - v_take;
          v_left        := v_left - v_take;
        end if;
      end if;

      -- 2. FIFO spill, confined to the settlement's own book
      v_i := 1;
      while v_left > 0 and v_i <= v_n loop
        if v_rem[v_i] > 0 and (v_scope is null or v_opening[v_i] = v_scope) then
          v_take      := least(v_left, v_rem[v_i]);
          v_rem[v_i]  := v_rem[v_i] - v_take;
          v_left      := v_left - v_take;
        end if;
        v_i := v_i + 1;
      end loop;
      -- Any v_left still > 0 means either an over-settlement, which the
      -- constraint trigger in 0002 prevents, or a book that has since shrunk
      -- below what was settled against it. Nothing to do here either way:
      -- reporting it against a row in the other book is exactly what this file
      -- exists to stop.
    end loop;

    for v_i in 1 .. v_n loop
      transaction_id  := v_ids[v_i];
      amount_minor    := v_amounts[v_i];
      remaining_minor := v_rem[v_i];
      settled_minor   := v_amounts[v_i] - v_rem[v_i];
      status := case
                  when v_rem[v_i] = 0             then 'settled'
                  when v_rem[v_i] = v_amounts[v_i] then 'open'
                  else 'partial'
                end;
      return next;
    end loop;
  end loop;
end;
$$;

comment on function public.transaction_settlement_status(uuid) is
  'FIFO settlement allocation per transaction. A settlement pays down the row it names first; the remainder spills oldest-first across that row''s own book — opening or regular — and an account-level settlement spills across both (0003, scoped 0023).';

-- -----------------------------------------------------------------------------
-- The invariant 0022 installed, re-checked against live data after the change.
-- -----------------------------------------------------------------------------

do $$
declare v_bad bigint;
begin
  select count(*) into v_bad
  from public.person_balances b
  where b.cash_in_hand_minor + b.opening_net_minor <> b.net_balance;

  if v_bad > 0 then
    raise exception
      '0023: % account(s) where cash_in_hand + opening_net <> net_balance.', v_bad;
  end if;

  raise notice
    '0023: settlement spill scoped to its own book. cash_in_hand + opening_net = net_balance still holds for every account; no amount was rewritten.';
end $$;
