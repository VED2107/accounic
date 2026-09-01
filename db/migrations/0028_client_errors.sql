-- =============================================================================
-- 0028_client_errors.sql
-- Production error telemetry (milestone 1.9.0, Phase 2).
--
-- Until now a production failure was invisible. `web/src/lib/errors.ts` logged
-- only outside production, and the Flutter client logged to a console nobody
-- can read on a phone — which is why every bug since v1.0.0 was found by one
-- person using the app and noticing.
--
-- WHERE THE REPORTS GO, AND WHY HERE.
--
-- Not to a third party. This is an accounting product: a crash report from it
-- carries a route, an operation and a stack — and, if anyone is careless, a
-- balance, a person's name or the note on a payment. Sending that to a service
-- outside the workspace is a decision with consequences that cannot be undone
-- once it is in someone else's index. Reports land in the owner's own database,
-- under the same RLS as their ledger, and the clients sanitise before sending.
--
-- The clients call one RPC, so pointing them at Sentry later is a change to one
-- function on each side, not to every call site.
--
-- WHAT MAY BE SENT — and the table cannot hold anything else:
--
--     app, platform, app version, environment   which build failed
--     route / screen, operation                 what the user was doing
--     error type, a sanitised message           what went wrong
--     fingerprint                               so repeats group
--
-- WHAT MAY NEVER BE SENT: amounts, notes, descriptions, person names, phone
-- numbers, email addresses, tokens, keys. The clients strip them; the column
-- list gives them nowhere to land; and `report_client_error()` truncates and
-- redacts again on the way in, because a client is a thing that can be wrong.
-- =============================================================================

create table if not exists public.client_errors (
  id           uuid primary key default gen_random_uuid(),

  -- Null when the failure happened before or during sign-in, which is exactly
  -- the case worth keeping: an auth error nobody can report is a silent wall.
  owner_id     uuid references auth.users (id) on delete cascade,

  occurred_at  timestamptz not null default now(),

  app          text not null check (app in ('web', 'android', 'windows', 'ios', 'macos', 'linux')),
  app_version  text check (app_version is null or char_length(app_version) <= 40),
  environment  text not null default 'production'
               check (environment in ('production', 'development', 'test')),

  -- Where in the product. A route, never a URL with parameters in it.
  route        text check (route is null or char_length(route) <= 120),
  -- What was being attempted: 'create_transaction', 'load_dashboard', 'export'.
  operation    text check (operation is null or char_length(operation) <= 80),

  error_type   text not null check (char_length(error_type) <= 120),
  message      text not null check (char_length(message) <= 500),

  -- Stable across occurrences of the same fault, so a hundred reports of one
  -- bug read as one bug.
  fingerprint  text not null check (char_length(fingerprint) <= 64),

  -- Deliberately narrow and deliberately not free-form: see the whitelist in
  -- report_client_error() below.
  context      jsonb not null default '{}'::jsonb,

  created_at   timestamptz not null default now()
);

create index if not exists client_errors_owner_time_idx
  on public.client_errors (owner_id, occurred_at desc);
create index if not exists client_errors_fingerprint_idx
  on public.client_errors (fingerprint, occurred_at desc);

comment on table public.client_errors is
  'Sanitised client crash reports. Carries no amount, note, name or credential — see 0028.';

alter table public.client_errors enable row level security;
alter table public.client_errors force  row level security;

revoke all on public.client_errors from anon, authenticated;
grant select on public.client_errors to authenticated;

-- A user may read their own reports and nobody else's. Nobody writes directly:
-- every insert goes through the RPC below, which is what makes the sanitising
-- unavoidable rather than optional.
drop policy if exists client_errors_own on public.client_errors;
create policy client_errors_own on public.client_errors
  for select to authenticated using (owner_id = auth.uid());

-- -----------------------------------------------------------------------------
-- The one way in.
--
-- SECURITY DEFINER so the table needs no INSERT grant to anyone, and so an
-- unauthenticated failure — the sign-in screen throwing — can still be
-- reported without opening the table to `anon` for anything else.
--
-- Everything it is given is treated as hostile: truncated to the column widths,
-- stripped of anything that looks like an amount, an email address, a phone
-- number or a long digit run, and — for `context` — reduced to a fixed set of
-- keys with short scalar values.
-- -----------------------------------------------------------------------------

create or replace function public.redact_for_telemetry(p_text text)
returns text
language sql
immutable
set search_path = ''
as $$
  select
    case when p_text is null then null
    else
      regexp_replace(
        regexp_replace(
          regexp_replace(
            regexp_replace(p_text, '[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}', '[email]', 'g'),
            -- Anything money-shaped: 1,234.56 / 1234.56 / ₹1234
            '[0-9]{1,3}(,[0-9]{3})+(\.[0-9]+)?|[0-9]+\.[0-9]{2,}', '[amount]', 'g'),
          -- Any run of 7+ digits: phone numbers, ids, account numbers.
          '[0-9]{7,}', '[number]', 'g'),
        -- A UUID identifies a person or an entry. The fingerprint does the
        -- grouping; the id would only ever be used to look someone up.
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        '[id]', 'g')
    end
$$;

comment on function public.redact_for_telemetry(text) is
  'Second line of defence: strips emails, money-shaped numbers, long digit runs and UUIDs from a report.';

create or replace function public.report_client_error(
  p_app         text,
  p_error_type  text,
  p_message     text,
  p_fingerprint text,
  p_app_version text default null,
  p_environment text default 'production',
  p_route       text default null,
  p_operation   text default null,
  p_context     jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_owner uuid := auth.uid();
  v_id    uuid;
  v_ctx   jsonb := '{}'::jsonb;
  v_key   text;
  v_val   jsonb;
begin
  if p_app is null or p_error_type is null or p_message is null or p_fingerprint is null then
    raise exception 'A report needs an app, a type, a message and a fingerprint.'
      using errcode = 'check_violation';
  end if;

  -- One bucket of its own: a client stuck in a crash loop must not be able to
  -- fill the ledger's write budget, or the table (0026).
  perform public.enforce_rate_limit('telemetry');

  -- The context whitelist. Anything not named here is dropped, and what is kept
  -- is redacted and truncated. A client that sends `{"amount": 500000}` gets a
  -- row with no amount in it.
  for v_key, v_val in select * from jsonb_each(coalesce(p_context, '{}'::jsonb)) loop
    if v_key in ('screen', 'action', 'status_code', 'sqlstate', 'attempt',
                 'is_offline', 'locale', 'theme', 'device_class', 'os_version',
                 'flutter_version', 'duration_ms', 'entry_count') then
      v_ctx := v_ctx || jsonb_build_object(
        v_key,
        case
          when jsonb_typeof(v_val) = 'string'
            then to_jsonb(left(public.redact_for_telemetry(v_val #>> '{}'), 80))
          when jsonb_typeof(v_val) in ('number', 'boolean') then v_val
          else to_jsonb('[dropped]'::text)
        end
      );
    end if;
  end loop;

  insert into public.client_errors (
    owner_id, app, app_version, environment, route, operation,
    error_type, message, fingerprint, context
  )
  values (
    v_owner,
    left(p_app, 20),
    left(p_app_version, 40),
    case when p_environment in ('production', 'development', 'test')
         then p_environment else 'production' end,
    left(public.redact_for_telemetry(p_route), 120),
    left(p_operation, 80),
    left(public.redact_for_telemetry(p_error_type), 120),
    left(public.redact_for_telemetry(p_message), 500),
    left(p_fingerprint, 64),
    v_ctx
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.report_client_error(text, text, text, text, text, text, text, text, jsonb)
  from public;
grant execute on function public.report_client_error(text, text, text, text, text, text, text, text, jsonb)
  to authenticated, anon;

comment on function public.report_client_error(text, text, text, text, text, text, text, text, jsonb) is
  'The only way a crash report enters the database. Redacts, truncates and whitelists everything it is given.';

-- Telemetry gets its own rate-limit bucket, generous enough for a genuine crash
-- loop to be recorded a few times and mean enough that it cannot be a flood.
insert into public.rate_limits (bucket, max_events, window_seconds, note) values
  ('telemetry', 30, 300, 'Crash reports. A loop reports a few times, not forever.')
on conflict (bucket) do nothing;

-- -----------------------------------------------------------------------------
-- What an operator actually looks at: distinct faults, newest first.
-- -----------------------------------------------------------------------------

create or replace function public.my_error_summary(p_days int default 14)
returns jsonb
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(jsonb_agg(to_jsonb(r) order by r.last_seen desc), '[]'::jsonb)
  from (
    select
      e.fingerprint,
      min(e.error_type)              as error_type,
      min(e.message)                 as message,
      count(*)::bigint               as occurrences,
      min(e.occurred_at)             as first_seen,
      max(e.occurred_at)             as last_seen,
      array_agg(distinct e.app)      as apps,
      array_agg(distinct coalesce(e.app_version, 'unknown')) as versions,
      array_agg(distinct coalesce(e.route, 'unknown'))       as routes
    from public.client_errors e
    where e.owner_id = auth.uid()
      and e.occurred_at > now() - make_interval(days => greatest(1, least(coalesce(p_days, 14), 90)))
    group by e.fingerprint
  ) r
$$;

grant execute on function public.my_error_summary(int) to authenticated;

comment on function public.my_error_summary(int) is
  'The caller''s own crash reports, grouped by fault: what broke, where, in which build, how often.';
