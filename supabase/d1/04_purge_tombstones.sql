-- ===========================================================================
-- 4. TOMBSTONE PURGE  (optional — schedule once the migration has settled)
-- ===========================================================================
-- A tombstone's whole job is to outlive the last device that still held the item. 90 days
-- is far beyond any realistic offline window for two always-on devices. A device offline
-- longer than that could resurrect a deleted reminder; accepted.
create or replace function public.purge_nudge_tombstones() returns void
language sql security definer set search_path = public as $$
  delete from public.reminders
    where deleted_at is not null
      and deleted_at < to_char((now() - interval '90 days') at time zone 'utc',
                               'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  delete from public.lists
    where deleted_at is not null
      and deleted_at < to_char((now() - interval '90 days') at time zone 'utc',
                               'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  delete from public.smart_lists
    where deleted_at is not null
      and deleted_at < to_char((now() - interval '90 days') at time zone 'utc',
                               'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
$$;

-- With pg_cron enabled:
--   select cron.schedule('nudge-purge-tombstones', '0 4 * * 0', 'select public.purge_nudge_tombstones()');
