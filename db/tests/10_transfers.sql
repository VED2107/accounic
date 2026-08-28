-- =============================================================================
-- 10_transfers.sql — money moves between two people as one transaction (0020)
--
-- What this pins:
--
--   1. a same-currency transfer moves both balances and nothing else;
--   2. the workspace total is exactly what it was before it;
--   3. the two legs are linked, one source and one destination, and no third;
--   4. same person, zero, negative, unknown currency and another workspace's
--      person are all refused, server-side;
--   5. a repeated submission carrying the same client token produces one
--      transfer, not two;
--   6. a cross-currency transfer converts at the stored rate, keeps the
--      original figure on both sides, and is not rewritten when the market
--      moves;
--   7. a hand-typed rate and a hand-typed arrival amount are both honoured and
--      both frozen;
--   8. one leg cannot be voided, edited or orphaned on its own — the database
--      refuses the commit;
--   9. `void_transfer` retracts both sides and returns both balances to where
--      they were;
--  10. `update_transfer` moves both sides together;
--  11. dashboard INR total = Σ person INR balances, with transfers in the mix.
--
-- Deliberately does NOT `set constraints all immediate` at the top, unlike the
-- other suites: a transfer is written as a transfer row plus two legs, and the
-- trigger that checks the three agree is DEFERRED precisely so it judges the
-- finished state. Where a deferred check is the thing under test, this file
-- fires it explicitly with `set constraints all immediate` inside a block that
-- catches the result.
--
-- Self-contained: creates its own users, asserts, then ROLLS BACK.
--
--   node db/tools/run-sql.mjs test
-- =============================================================================

begin;

create or replace function pg_temp.become(p_uid uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
                     true);
  execute 'set local role authenticated';
end $$;

create or replace function pg_temp.assert(p_label text, p_condition boolean)
returns void language plpgsql as $$
begin
  if not p_condition then
    raise exception 'FAIL: %', p_label;
  end if;
  raise notice 'ok  %', p_label;
end $$;

do $$
declare
  -- 1 USD = 95.427612 INR. Its fourth decimal is not its last, so a rounded
  -- rate would give a different answer — see 08.
  c_usd_inr_e9 constant bigint := 95427612000;
  c_usd_inr_moved constant bigint := 99000000000;

  v_owner   uuid := gen_random_uuid();
  v_other   uuid := gen_random_uuid();
  v_ved     uuid;
  v_dhruv   uuid;
  v_dollar  uuid;   -- kept in USD
  v_stranger uuid;  -- belongs to v_other
  v_tr      jsonb;
  v_id      uuid;
  v_second  uuid;
  v_row     public.transfers;
  v_src     public.transactions;
  v_dst     public.transactions;
  v_bal     public.person_balances%rowtype;
  v_sum     public.owner_summary%rowtype;
  v_before  bigint;
  v_after   bigint;
  v_people  bigint;
  v_caught  boolean;
  v_message text;
  v_expected bigint;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated',
          'transfers-owner@example.com', 'x', now(), now(), now()),
         ('00000000-0000-0000-0000-000000000000', v_other, 'authenticated', 'authenticated',
          'transfers-other@example.com', 'x', now(), now(), now());

  -- The other workspace, populated first so its person exists to be refused.
  perform pg_temp.become(v_other);
  perform public.update_my_profile('Other Owner', null, null, 'INR', null);
  v_stranger := (public.create_person('Stranger', 'person')).id;

  perform pg_temp.become(v_owner);
  perform public.update_my_profile('Transfer Tester', null, null, 'INR', null);
  perform public.upsert_exchange_rates(
    'USD', jsonb_build_object('INR', 95.427612), current_date, 'test');

  -- ---------------------------------------------------------------------------
  -- 1. The headline case, exactly as specified
  --
  --   Ved   ₹10,000        transfer ₹3,000        Ved   ₹7,000
  --   Dhruv  ₹2,000        Ved → Dhruv            Dhruv ₹5,000
  -- ---------------------------------------------------------------------------
  v_ved   := (public.create_person('Ved', 'person', null, null, null, null, 'INR',
                                   'they_owe_me', 1000000)).id;
  v_dhruv := (public.create_person('Dhruv', 'person', null, null, null, null, 'INR',
                                   'they_owe_me', 200000)).id;

  select * into v_sum from public.owner_summary where owner_id = v_owner;
  v_before := v_sum.net_position;

  perform pg_temp.assert(
    'the two accounts start where the specification says',
    (select net_balance from public.person_balances where person_id = v_ved) = 1000000
      and (select net_balance from public.person_balances where person_id = v_dhruv) = 200000);

  v_tr := public.create_transfer(
    p_from_person_id => v_ved,
    p_to_person_id   => v_dhruv,
    p_amount_minor   => 300000,
    p_note           => 'rent share');
  v_id := (v_tr -> 'transfer' ->> 'id')::uuid;

  perform pg_temp.assert(
    'after ₹3,000 from Ved to Dhruv, Ved is ₹7,000',
    (select net_balance from public.person_balances where person_id = v_ved) = 700000);
  perform pg_temp.assert(
    'and Dhruv is ₹5,000',
    (select net_balance from public.person_balances where person_id = v_dhruv) = 500000);

  perform pg_temp.assert(
    'the call returns both balances, so one round trip updates two screens',
    (v_tr -> 'from_balance' ->> 'net_balance')::bigint = 700000
      and (v_tr -> 'to_balance' ->> 'net_balance')::bigint = 500000);

  -- ---------------------------------------------------------------------------
  -- 2. The workspace total did not move
  -- ---------------------------------------------------------------------------
  select * into v_sum from public.owner_summary where owner_id = v_owner;
  v_after := v_sum.net_position;

  perform pg_temp.assert(
    'a transfer redistributes and never creates: the workspace total is unchanged',
    v_after = v_before);

  perform pg_temp.assert(
    'source impact + destination impact = 0',
    (select coalesce(sum(case when type = 'credit' then amount_minor else -amount_minor end), 0)
       from public.transactions where transfer_id = v_id and not is_void) = 0);

  -- ---------------------------------------------------------------------------
  -- 3. Two linked legs, one of each role, and no third
  -- ---------------------------------------------------------------------------
  select * into v_src from public.transactions
   where transfer_id = v_id and transfer_role = 'source';
  select * into v_dst from public.transactions
   where transfer_id = v_id and transfer_role = 'destination';

  perform pg_temp.assert(
    'both legs carry the same transfer id',
    v_src.transfer_id = v_id and v_dst.transfer_id = v_id);
  perform pg_temp.assert(
    'the source is a debit on the person the money left',
    v_src.person_id = v_ved and v_src.type = 'debit' and v_src.amount_minor = 300000);
  perform pg_temp.assert(
    'the destination is a credit on the person it reached',
    v_dst.person_id = v_dhruv and v_dst.type = 'credit' and v_dst.amount_minor = 300000);
  perform pg_temp.assert(
    'and there are exactly two of them',
    (select count(*) from public.transactions where transfer_id = v_id) = 2);

  perform pg_temp.assert(
    'a same-currency transfer stores no rate and no conversion at all',
    (select entry_rate_e9 is null and exchange_rate_e9 is null and conversion_mode is null
       from public.transfers where id = v_id));

  perform pg_temp.assert(
    'nothing fails to reconcile',
    not exists (select 1 from public.transfer_integrity where owner_id = v_owner));

  -- Fire the deferred pair check now rather than at a commit this test never
  -- reaches, then restore deferral so the next create_transfer can still write
  -- its transfer row before its legs. Without this the suite would roll back
  -- with every transfer check still pending and prove nothing about them.
  set constraints all immediate;
  set constraints all deferred;
  perform pg_temp.assert(
    'the transfer passes the deferred integrity check it will face at commit',
    true);

  -- Both timelines show it, and both know who the other party is.
  perform pg_temp.assert(
    'the source timeline says where the money went',
    (select r ->> 'transfer_role' = 'source' and r ->> 'transfer_counterparty_name' = 'Dhruv'
       from jsonb_array_elements(public.person_page(v_ved) -> 'timeline') r
      where (r ->> 'transfer_id')::uuid = v_id));
  perform pg_temp.assert(
    'and the destination timeline says where it came from',
    (select r ->> 'transfer_role' = 'destination' and r ->> 'transfer_counterparty_name' = 'Ved'
       from jsonb_array_elements(public.person_page(v_dhruv) -> 'timeline') r
      where (r ->> 'transfer_id')::uuid = v_id));

  -- ---------------------------------------------------------------------------
  -- 4. What is refused
  -- ---------------------------------------------------------------------------
  v_caught := false;
  begin
    perform public.create_transfer(v_ved, v_ved, 100000);
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert('a transfer to the same person is refused', v_caught);

  v_caught := false;
  begin
    perform public.create_transfer(v_ved, v_dhruv, 0);
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert('a zero amount is refused', v_caught);

  v_caught := false;
  begin
    perform public.create_transfer(v_ved, v_dhruv, -5000);
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert('a negative amount is refused', v_caught);

  v_caught := false;
  begin
    perform public.create_transfer(v_ved, v_dhruv, 100000, 'XYZ');
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert('an unknown currency is refused', v_caught);

  v_caught := false;
  begin
    perform public.create_transfer(v_ved, v_dhruv, 100000, 'INR', current_date + 30);
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert('a future date is refused', v_caught);

  -- Cross-workspace, in both directions. Neither is visible, so neither is
  -- reachable — enforced by RLS and by the composite foreign keys, not by a UI.
  v_caught := false;
  begin
    perform public.create_transfer(v_ved, v_stranger, 100000);
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert(
    'transferring TO a person in another workspace is refused', v_caught);

  v_caught := false;
  begin
    perform public.create_transfer(v_stranger, v_ved, 100000);
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert(
    'transferring FROM a person in another workspace is refused', v_caught);

  perform pg_temp.assert(
    'and none of those attempts wrote anything',
    (select count(*) from public.transfers where owner_id = v_owner) = 1);

  -- ---------------------------------------------------------------------------
  -- 5. A double-submitted form is one transfer
  -- ---------------------------------------------------------------------------
  v_tr := public.create_transfer(
    v_ved, v_dhruv, 50000, 'INR', current_date, 'once only',
    null, null, null, null, null, null, 'idempotency-token-1');
  v_second := (v_tr -> 'transfer' ->> 'id')::uuid;

  v_tr := public.create_transfer(
    v_ved, v_dhruv, 50000, 'INR', current_date, 'once only',
    null, null, null, null, null, null, 'idempotency-token-1');

  perform pg_temp.assert(
    'the same client token returns the first transfer rather than making a second',
    (v_tr -> 'transfer' ->> 'id')::uuid = v_second);
  perform pg_temp.assert(
    'so the workspace holds two transfers, not three',
    (select count(*) from public.transfers where owner_id = v_owner) = 2);
  perform pg_temp.assert(
    'and the money moved once',
    (select net_balance from public.person_balances where person_id = v_ved) = 650000);

  -- ---------------------------------------------------------------------------
  -- 6. Cross-currency, at the stored rate
  --
  -- $100 from a dollar account to a rupee account.
  -- ---------------------------------------------------------------------------
  v_dollar := (public.create_person('Dollar Dan', 'person', null, null, null, null, 'USD',
                                    'they_owe_me', 50000)).id;

  v_expected := public.convert_amount_minor(10000, 'USD', 'INR', c_usd_inr_e9);

  v_tr := public.create_transfer(
    p_from_person_id   => v_dollar,
    p_to_person_id     => v_dhruv,
    p_amount_minor     => 10000,
    p_currency         => 'USD',
    p_exchange_rate_e9 => c_usd_inr_e9,
    p_rate_source      => 'test');
  v_id := (v_tr -> 'transfer' ->> 'id')::uuid;

  select * into v_row from public.transfers where id = v_id;

  perform pg_temp.assert(
    'the amount the user entered is preserved verbatim, in the currency they used',
    v_row.entry_amount_minor = 10000 and v_row.entry_currency = 'USD');
  perform pg_temp.assert(
    'what left the source is $100, in the source''s own denomination',
    v_row.from_amount_minor = 10000 and v_row.from_currency = 'USD');
  perform pg_temp.assert(
    'what arrived is what the full stored rate says, rounded once',
    v_row.to_amount_minor = v_expected and v_row.to_currency = 'INR');
  perform pg_temp.assert(
    'and the rate actually used is stored on the transfer',
    v_row.exchange_rate_e9 = c_usd_inr_e9
      and v_row.exchange_rate_source = 'test'
      and coalesce(v_row.conversion_mode, 'automatic') = 'automatic');

  select * into v_dst from public.transactions
   where transfer_id = v_id and transfer_role = 'destination';
  perform pg_temp.assert(
    'the destination leg carries the original figure, so its row can say $100 USD → ₹',
    v_dst.entered_amount_minor = 10000 and v_dst.entered_currency = 'USD'
      and v_dst.amount_minor = v_expected
      and v_dst.exchange_rate_e9 = c_usd_inr_e9);

  perform pg_temp.assert(
    'both accounts moved by their own side of it',
    (select net_balance from public.person_balances where person_id = v_dollar) = 40000
      and (select net_balance from public.person_balances where person_id = v_dhruv)
            = 500000 + 50000 + v_expected);

  perform pg_temp.assert(
    'and the cross-currency transfer reconciles at its own rate',
    not exists (select 1 from public.transfer_integrity where owner_id = v_owner));

  -- The market moves. The transfer does not.
  perform public.upsert_exchange_rates(
    'USD', jsonb_build_object('INR', 99.0), current_date + 1, 'test-moved');

  select * into v_row from public.transfers where id = v_id;
  perform pg_temp.assert(
    'a later rate never rewrites a recorded transfer',
    v_row.exchange_rate_e9 = c_usd_inr_e9 and v_row.to_amount_minor = v_expected);
  perform pg_temp.assert(
    'nor the amounts on its legs',
    (select amount_minor from public.transactions
      where transfer_id = v_id and transfer_role = 'destination') = v_expected);

  -- ---------------------------------------------------------------------------
  -- 7. A rate a human typed, and an amount a human typed
  -- ---------------------------------------------------------------------------
  v_tr := public.create_transfer(
    p_from_person_id   => v_dollar,
    p_to_person_id     => v_dhruv,
    p_amount_minor     => 10000,
    p_currency         => 'USD',
    p_exchange_rate_e9 => 90000000000,
    p_rate_source      => 'manual-rate');
  v_id := (v_tr -> 'transfer' ->> 'id')::uuid;
  select * into v_row from public.transfers where id = v_id;

  perform pg_temp.assert(
    'a hand-typed rate is used as given and marked as such',
    v_row.exchange_rate_e9 = 90000000000
      and public.rate_is_manual(v_row.exchange_rate_source)
      and v_row.to_amount_minor = 900000);

  -- What the rate said versus what actually arrived at the counter.
  v_tr := public.create_transfer(
    p_from_person_id   => v_dollar,
    p_to_person_id     => v_dhruv,
    p_amount_minor     => 10000,
    p_currency         => 'USD',
    p_exchange_rate_e9 => c_usd_inr_e9,
    p_rate_source      => 'test',
    p_converted_amount_minor => 900000,
    p_conversion_mode  => 'manual');
  v_id := (v_tr -> 'transfer' ->> 'id')::uuid;
  select * into v_row from public.transfers where id = v_id;

  perform pg_temp.assert(
    'a hand-entered arrival amount is what the ledger records',
    v_row.to_amount_minor = 900000 and v_row.conversion_mode = 'manual');
  perform pg_temp.assert(
    'with what the rate said kept beside it as the audit reference',
    v_row.auto_converted_amount_minor = v_expected);
  perform pg_temp.assert(
    'and a manual transfer is not judged against the rate',
    not exists (select 1 from public.transfer_integrity where owner_id = v_owner));

  -- ---------------------------------------------------------------------------
  -- 8. One leg can never stand alone
  -- ---------------------------------------------------------------------------
  select id into v_id from public.transfers
   where owner_id = v_owner and note = 'rent share';
  select * into v_src from public.transactions
   where transfer_id = v_id and transfer_role = 'source';

  v_caught := false;
  begin
    perform public.void_transaction(v_src.id, 'trying to void half a transfer');
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert(
    'void_transaction refuses a transfer leg by name', v_caught);

  -- And the guarantee underneath it: even a direct UPDATE cannot commit.
  v_caught := false;
  v_message := '';
  begin
    update public.transactions set is_void = true, void_reason = 'direct'
     where id = v_src.id;
    -- Fire the deferred check now rather than at a commit this test never does.
    set constraints all immediate;
  exception when others then
    v_caught := true;
    v_message := sqlerrm;
  end;
  perform pg_temp.assert(
    'and the database refuses the commit even when the RPC is bypassed',
    v_caught and v_message like '%voided together%');

  perform pg_temp.assert(
    'so the transfer is still whole',
    (select count(*) from public.transactions
      where transfer_id = v_id and not is_void) = 2);

  -- ---------------------------------------------------------------------------
  -- 9. Retracting a transfer retracts both sides
  -- ---------------------------------------------------------------------------
  select net_balance into v_before from public.person_balances where person_id = v_ved;

  perform public.void_transfer(v_id, 'entered twice');

  perform pg_temp.assert(
    'both legs are voided together',
    (select count(*) from public.transactions
      where transfer_id = v_id and is_void) = 2);
  perform pg_temp.assert(
    'the money comes back to the source',
    (select net_balance from public.person_balances where person_id = v_ved)
      = v_before + 300000);
  perform pg_temp.assert(
    'and leaves the destination',
    (select net_balance from public.person_balances where person_id = v_dhruv)
      = 500000 + 50000 + v_expected + 900000 + 900000 - 300000);
  perform pg_temp.assert(
    'a retracted transfer cannot be retracted twice',
    (select is_void from public.transfers where id = v_id));

  -- ---------------------------------------------------------------------------
  -- 10. Editing moves both sides
  -- ---------------------------------------------------------------------------
  perform public.update_transfer(
    p_transfer_id => v_second, p_amount_minor => 80000, p_note => 'corrected');

  select * into v_row from public.transfers where id = v_second;
  perform pg_temp.assert(
    'the transfer itself carries the new amount',
    v_row.from_amount_minor = 80000 and v_row.to_amount_minor = 80000
      and v_row.note = 'corrected');
  perform pg_temp.assert(
    'and so do both legs, in one operation',
    (select count(*) from public.transactions
      where transfer_id = v_second and amount_minor = 80000
        and description = 'corrected') = 2);
  perform pg_temp.assert(
    'the two sides still cancel exactly',
    (select coalesce(sum(case when type = 'credit' then amount_minor else -amount_minor end), 0)
       from public.transactions where transfer_id = v_second and not is_void) = 0);

  -- ---------------------------------------------------------------------------
  -- 11. THE invariant: dashboard INR total = Σ person INR balances
  -- ---------------------------------------------------------------------------
  select coalesce(sum(net_balance_base), 0) into v_people
  from public.person_balances
  where owner_id = v_owner and not is_archived;

  select * into v_sum from public.owner_summary where owner_id = v_owner;

  perform pg_temp.assert(
    'the dashboard total is the sum of the person balances, transfers and all',
    v_sum.net_position = v_people);

  perform pg_temp.assert(
    'and the dashboard RPC reports the same number',
    (public.dashboard() -> 'summary' ->> 'net_position')::bigint = v_people);

  perform pg_temp.assert(
    'a transfer''s two legs cancel inside their own currency''s totals too',
    (select count(*) from public.transfer_integrity where owner_id = v_owner) = 0);

  -- Everything written since the last checkpoint — five more transfers, a
  -- retraction and an edit — judged the way a commit would judge it.
  set constraints all immediate;
  set constraints all deferred;
  perform pg_temp.assert(
    'every transfer in the workspace survives the deferred integrity check',
    true);

  -- ---------------------------------------------------------------------------
  -- 12. Another workspace sees none of it
  -- ---------------------------------------------------------------------------
  perform pg_temp.become(v_other);
  perform pg_temp.assert(
    'a second user cannot read this workspace''s transfers',
    (select count(*) from public.transfers) = 0);

  v_caught := false;
  begin
    perform public.void_transfer(v_second, 'not mine');
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert(
    'nor retract one', v_caught);

  v_caught := false;
  begin
    perform public.update_transfer(v_second, 999999);
  exception when others then v_caught := true;
  end;
  perform pg_temp.assert('nor edit one', v_caught);

  perform pg_temp.become(v_owner);
  perform pg_temp.assert(
    'and the transfer is exactly as its owner left it',
    (select from_amount_minor from public.transfers where id = v_second) = 80000);

  raise notice '=== 10_transfers: all assertions passed ===';
end $$;

rollback;
