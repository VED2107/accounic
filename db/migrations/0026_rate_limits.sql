-- =============================================================================
-- 0026_rate_limits.sql
-- Write rate limiting (milestone 1.9.0, Phase 9).
--
-- The project URL and the anon key are public by design — they ship inside the
-- APK and the browser bundle — so anything an authenticated session can do, a
-- script holding that session can do in a loop. RLS decides WHOSE data can be
-- touched; nothing until now decided HOW FAST.
--
-- Two decisions shape this file:
--
--   1. IT IS A TRIGGER, NOT A CHANGE TO THE RPCs. Every write already lands in
--      one of four tables, and a trigger there covers the RPCs, any future RPC,
--      and a direct PostgREST insert alike — without rewriting a single
--      accounting function. Nothing in the engine had to be touched to gain it.
--   2. READS ARE NOT LIMITED. A user refreshing a dashboard is not an abuse
--      case, and a limit that fires while someone is reading their own books
--      would be a bug that looks like a security feature.
--
-- The limits are deliberately far above human use: 120 writes a minute is two
-- a second, sustained, which no thumb produces. A phone that syncs a backlog
-- after a flight stays well inside them; a script hammering create_transaction
-- does not.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- What the limits are. A table, not constants, so they can be changed without a
-- migration — and read by an operator without reading the source.
-- -----------------------------------------------------------------------------

create table if not exists public.rate_limits (
  bucket         text primary key,
  max_events     int  not null check (max_events > 0),
  window_seconds int  not null check (window_seconds > 0),
  note           text,
  updated_at     timestamptz not null default now()
);

comment on table public.rate_limits is
  'Per-bucket write limits. Editable by the service role only; read by enforce_rate_limit().';

insert into public.rate_limits (bucket, max_events, window_seconds, note) values
  ('transactions', 120, 60,   'Ledger entries. Two a second sustained — far above any thumb.'),
  ('settlements',  120, 60,   'Settlements, including the opening-balance path.'),
  ('people',        60, 60,   'Accounts created or renamed.'),
  ('transfers',     60, 60,   'Transfers write two legs; each counts once here.'),
  ('writes',      2000, 3600, 'Everything above, together, over an hour.')
on conflict (bucket) do nothing;

-- -----------------------------------------------------------------------------
-- The counters. One row per owner, per bucket, per window.
--
-- A fixed window rather than a sliding one: it is one upsert per write and no
-- history to prune, and the failure mode of a fixed window — twice the limit
-- across a boundary — is irrelevant at limits set this far above real use.
-- -----------------------------------------------------------------------------

create table if not exists public.rate_limit_counters (
  owner_id     uuid        not null references auth.users (id) on delete cascade,
  bucket       text        not null,
  window_start timestamptz not null,
  events       int         not null default 0,
  primary key (owner_id, bucket, window_start)
);

create index if not exists rate_limit_counters_window_idx
  on public.rate_limit_counters (window_start);

comment on table public.rate_limit_counters is
  'Fixed-window write counters. Written only by enforce_rate_limit(); readable by the owner.';

alter table public.rate_limits          enable row level security;
alter table public.rate_limits          force  row level security;
alter table public.rate_limit_counters  enable row level security;
alter table public.rate_limit_counters  force  row level security;

revoke all on public.rate_limits         from anon, authenticated;
revoke all on public.rate_limit_counters from anon, authenticated;

grant select on public.rate_limits         to authenticated;
grant select on public.rate_limit_counters to authenticated;

drop policy if exists rate_limits_read on public.rate_limits;
create policy rate_limits_read on public.rate_limits
  for select to authenticated using (true);

-- A user can see their own counters — useful when an app wants to explain why
-- it is being refused — and nobody else's.
drop policy if exists rate_limit_counters_own on public.rate_limit_counters;
create policy rate_limit_counters_own on public.rate_limit_counters
  for select to authenticated using (owner_id = auth.uid());

-- -----------------------------------------------------------------------------
-- enforce_rate_limit() — count one event, and refuse when the bucket is full.
--
-- SECURITY DEFINER because the counter table is deliberately not writable by
-- anyone: a caller who could update their own counter could reset it, which
-- would make the limit decorative. It writes nothing but the counter, and the
-- only owner it can ever count against is the caller's own.
--
-- ON CONFLICT DO UPDATE takes the row lock, so two concurrent writes from the
-- same session cannot both read 119 and both proceed.
-- -----------------------------------------------------------------------------

create or replace function public.enforce_rate_limit(p_bucket text)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner   uuid := auth.uid();
  v_limit   public.rate_limits%rowtype;
  v_start   timestamptz;
  v_events  int;
begin
  -- No session, no limit to apply: the write is about to be refused by RLS
  -- anyway, and counting it would let an anonymous caller fill someone's
  -- bucket.
  if v_owner is null then return 0; end if;

  select * into v_limit from public.rate_limits where bucket = p_bucket;
  if not found then return 0; end if;

  v_start := to_timestamp(
    floor(extract(epoch from clock_timestamp()) / v_limit.window_seconds)
      * v_limit.window_seconds
  );

  insert into public.rate_limit_counters (owner_id, bucket, window_start, events)
  values (v_owner, p_bucket, v_start, 1)
  on conflict (owner_id, bucket, window_start)
  do update set events = public.rate_limit_counters.events + 1
  returning events into v_events;

  if v_events > v_limit.max_events then
    raise exception
      'Too many % in a short time. Wait a moment and try again — nothing has been saved.',
      p_bucket
      using errcode = 'AC429',
            hint = format('limit %s per %s seconds', v_limit.max_events, v_limit.window_seconds);
  end if;

  return v_events;
end;
$$;

revoke all on function public.enforce_rate_limit(text) from public, anon;
grant execute on function public.enforce_rate_limit(text) to authenticated;

comment on function public.enforce_rate_limit(text) is
  'Counts one write against the caller''s bucket and raises SQLSTATE AC429 when it is full.';

-- -----------------------------------------------------------------------------
-- The trigger. INSERT only.
--
-- An UPDATE is a void, an edit, or a settlement being retracted — all of them
-- corrections, all of them things a user does deliberately and rarely, and none
-- of them worth risking a refusal on. The abuse case is creating rows.
-- -----------------------------------------------------------------------------

create or replace function public.rate_limit_write()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- The table's own bucket, then the shared hourly one. Both are counted, so a
  -- burst inside one table and a slow flood across all of them are both caught.
  perform public.enforce_rate_limit(tg_argv[0]);
  perform public.enforce_rate_limit('writes');
  return new;
end;
$$;

comment on function public.rate_limit_write() is
  'BEFORE INSERT trigger: counts the row against its table bucket and the shared hourly one.';

drop trigger if exists rate_limit_transactions on public.transactions;
create trigger rate_limit_transactions
  before insert on public.transactions
  for each row execute function public.rate_limit_write('transactions');

drop trigger if exists rate_limit_settlements on public.settlements;
create trigger rate_limit_settlements
  before insert on public.settlements
  for each row execute function public.rate_limit_write('settlements');

drop trigger if exists rate_limit_people on public.people;
create trigger rate_limit_people
  before insert on public.people
  for each row execute function public.rate_limit_write('people');

drop trigger if exists rate_limit_transfers on public.transfers;
create trigger rate_limit_transfers
  before insert on public.transfers
  for each row execute function public.rate_limit_write('transfers');

-- -----------------------------------------------------------------------------
-- Housekeeping. Counters older than a day are of no interest to anyone.
--
-- Called opportunistically rather than scheduled: this project has no cron, and
-- a table with one row per owner per window per day is not a problem worth a
-- background job. An operator can call it; so can a future scheduler.
-- -----------------------------------------------------------------------------

create or replace function public.prune_rate_limit_counters(p_older_than interval default '1 day')
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_removed bigint;
begin
  delete from public.rate_limit_counters
  where window_start < now() - p_older_than;
  get diagnostics v_removed = row_count;
  return v_removed;
end;
$$;

revoke all on function public.prune_rate_limit_counters(interval) from public, anon, authenticated;

comment on function public.prune_rate_limit_counters(interval) is
  'Deletes spent rate-limit windows. Service role only.';
