-- ===========================================================================
-- 6. REJECT OLDER WRITES  (2026-10-18)  — run once in the Supabase SQL editor
-- ===========================================================================
-- WHY: the apps upload with "upsert, merge duplicates", so the server kept whichever upload
-- ARRIVED LAST, not the newest edit. A device uploading a stale copy (an offline edit, a
-- slow request) could overwrite a newer edit from the other device, and the two devices then
-- disagreed about that reminder for good. Every row carries `updated_at` as fixed-width
-- canonical text (see CloudSync.swift), so plain string comparison is chronological.
--
-- WHAT: a BEFORE UPDATE trigger on the four synced tables. If an incoming update is strictly
-- OLDER than the row already stored, the update is skipped (RETURN NULL) and the newer row
-- stays. The request still succeeds — the app never sees an error. Equal or newer stamps
-- apply exactly as before. Inserts of new rows are unaffected.
--
-- SAFE TO RE-RUN. Touches no data. Undo: drop the four triggers and the function (bottom).

create or replace function public.nudge_reject_older_write()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.updated_at < old.updated_at then
    return null;      -- stale upload: keep the newer row that's already here
  end if;
  return new;
end;
$$;

drop trigger if exists nudge_reject_older_write on public.reminders;
create trigger nudge_reject_older_write before update on public.reminders
  for each row execute function public.nudge_reject_older_write();

drop trigger if exists nudge_reject_older_write on public.lists;
create trigger nudge_reject_older_write before update on public.lists
  for each row execute function public.nudge_reject_older_write();

drop trigger if exists nudge_reject_older_write on public.smart_lists;
create trigger nudge_reject_older_write before update on public.smart_lists
  for each row execute function public.nudge_reject_older_write();

drop trigger if exists nudge_reject_older_write on public.settings;
create trigger nudge_reject_older_write before update on public.settings
  for each row execute function public.nudge_reject_older_write();

-- ---------------------------------------------------------------------------
-- Hardening (only does anything if 04_purge_tombstones.sql was ever run):
-- purge_nudge_tombstones() is SECURITY DEFINER in the public schema, so by default anyone
-- holding the public anon key could call it through the API. It only deletes 90-day-old
-- tombstones, but there is no reason for any client to be able to call it.
do $$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
             where n.nspname = 'public' and p.proname = 'purge_nudge_tombstones') then
    execute 'revoke execute on function public.purge_nudge_tombstones() from public, anon, authenticated';
  end if;
end $$;

-- Check: should list 4 rows, one per table.
select event_object_table as table_name, trigger_name
from information_schema.triggers
where trigger_name = 'nudge_reject_older_write'
order by 1;

-- Row count, for the record (H2 — the app now pages its downloads, so >1000 is fine):
select count(*) as reminder_rows,
       count(*) filter (where deleted_at is not null) as tombstones
from public.reminders;

-- UNDO (only if ever needed):
--   drop trigger if exists nudge_reject_older_write on public.reminders;
--   drop trigger if exists nudge_reject_older_write on public.lists;
--   drop trigger if exists nudge_reject_older_write on public.smart_lists;
--   drop trigger if exists nudge_reject_older_write on public.settings;
--   drop function if exists public.nudge_reject_older_write();
