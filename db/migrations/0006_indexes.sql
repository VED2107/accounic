-- =============================================================================
-- 0006_indexes.sql
-- Indexes for the access patterns this product actually has (context.md §23).
--
-- Every RLS policy filters on owner_id, so owner_id leads every composite index
-- rather than sitting in one of its own.
-- =============================================================================

-- Views must not be reachable by anon; Supabase's default grants are broad.
revoke all on public.person_balances from anon;
revoke all on public.owner_summary   from anon;
revoke all on public.activity_feed   from anon;

-- --- people ------------------------------------------------------------------

-- People list: active people of one owner, alphabetical.
create index if not exists people_owner_active_name_idx
  on public.people (owner_id, name)
  where not is_archived;

create index if not exists people_owner_archived_idx
  on public.people (owner_id, is_archived);

-- Search by name / phone (context.md §15). trigram beats a leading-% LIKE scan.
create extension if not exists pg_trgm;

create index if not exists people_name_trgm_idx
  on public.people using gin (name gin_trgm_ops);

create index if not exists people_phone_trgm_idx
  on public.people using gin (phone gin_trgm_ops)
  where phone is not null;

-- --- transactions ------------------------------------------------------------

-- Person timeline, newest first: the single hottest query in the product.
create index if not exists transactions_owner_person_date_idx
  on public.transactions (owner_id, person_id, transaction_date desc, created_at desc);

-- Workspace-wide recent activity feed.
create index if not exists transactions_owner_date_idx
  on public.transactions (owner_id, transaction_date desc, created_at desc);

-- Balance aggregation: person + type, live rows only.
create index if not exists transactions_person_type_live_idx
  on public.transactions (person_id, type)
  include (amount_minor)
  where not is_void;

create index if not exists transactions_owner_created_idx
  on public.transactions (owner_id, created_at desc);

-- Note search (context.md §15).
create index if not exists transactions_description_trgm_idx
  on public.transactions using gin (description gin_trgm_ops)
  where description is not null;

-- --- settlements -------------------------------------------------------------

create index if not exists settlements_owner_person_date_idx
  on public.settlements (owner_id, person_id, settlement_date desc, created_at desc);

create index if not exists settlements_owner_date_idx
  on public.settlements (owner_id, settlement_date desc, created_at desc);

create index if not exists settlements_person_direction_live_idx
  on public.settlements (person_id, direction)
  include (amount_minor)
  where not is_void;

-- Allocation lookups from a transaction to its named settlements.
create index if not exists settlements_transaction_idx
  on public.settlements (transaction_id)
  where transaction_id is not null;

-- --- profiles ----------------------------------------------------------------

create unique index if not exists profiles_email_uniq on public.profiles (email);
create index if not exists profiles_active_idx on public.profiles (is_active);

analyze public.people;
analyze public.transactions;
analyze public.settlements;
