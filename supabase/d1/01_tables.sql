-- ===========================================================================
-- 1. TABLES
-- ===========================================================================
-- `updated_at` and `deleted_at` are TEXT, not timestamptz, and hold one canonical
-- fixed-width UTC form: 2026-07-10T13:00:00.123Z (see syncStamp() in CloudSync.swift).
-- Fixed width means lexicographic order == chronological order, so PostgREST's `gt.`
-- filter and the client's merge comparison agree exactly, with no date parsing on either
-- side. timestamptz would round-trip 6 fractional digits, which ISO8601DateFormatter on
-- the client refuses to parse.
--
-- `data` is NULL for a tombstone. `deleted_at` NULL means live.
-- The row's `updated_at` is "when these bytes last changed" and is the ONLY merge key.
-- It is deliberately not the same thing as the `updatedAt` inside `data`, which is the
-- item's last meaningful edit and is used to arbitrate against Apple's lastModifiedDate.

create table if not exists public.reminders (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id         text not null,
  data       jsonb,
  updated_at text not null,
  deleted_at text,
  primary key (user_id, id)
);

create table if not exists public.lists (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id         text not null,
  data       jsonb,
  updated_at text not null,
  deleted_at text,
  primary key (user_id, id)
);

create table if not exists public.smart_lists (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  id         text not null,
  data       jsonb,
  updated_at text not null,
  deleted_at text,
  primary key (user_id, id)
);

-- settings has no per-item identity: one row per user, merged whole on updated_at.
-- Small, low-churn, and nothing in the iOS app writes it today — it is round-tripped so
-- the retired web client's preferences survive.
create table if not exists public.settings (
  user_id    uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  data       jsonb,
  updated_at text not null
);

-- Delta pulls filter on (user_id, updated_at).
create index if not exists reminders_user_updated   on public.reminders   (user_id, updated_at);
create index if not exists lists_user_updated       on public.lists       (user_id, updated_at);
create index if not exists smart_lists_user_updated on public.smart_lists (user_id, updated_at);

alter table public.reminders   enable row level security;
alter table public.lists       enable row level security;
alter table public.smart_lists enable row level security;
alter table public.settings    enable row level security;

-- One policy per table. `with check` on the same predicate is what stops a client
-- inserting rows under someone else's user_id.
do $$
declare t text;
begin
  foreach t in array array['reminders','lists','smart_lists','settings'] loop
    execute format('drop policy if exists own_rows on public.%I', t);
    execute format(
      'create policy own_rows on public.%I for all
         using (auth.uid() = user_id) with check (auth.uid() = user_id)', t);
  end loop;
end $$;

-- Sanity: no leftover permissive policy (a `nudge owner only` policy keyed to the burned
-- user_key was found on nudge_data during the D2 work — check for its equivalent here).
select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename in ('reminders','lists','smart_lists','settings');
