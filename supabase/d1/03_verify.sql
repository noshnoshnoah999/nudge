-- ===========================================================================
-- 3. VERIFICATION — DO NOT SHIP THE NEW APP BUILD IF THIS RAISES
-- ===========================================================================
-- Counts must match the blob exactly. A shortfall means duplicate ids inside the blob
-- (silently swallowed by `on conflict do nothing`) or a null id — either way, stop and
-- look, because the app build will treat any missing row as "never existed".
do $$
declare
  blob_reminders int; row_reminders int;
  blob_lists     int; row_lists     int;
  blob_smart     int; row_smart     int;
begin
  select count(*) into blob_reminders
    from public.nudge_data d, lateral jsonb_array_elements(coalesce(d.data->'reminders','[]'::jsonb));
  select count(*) into blob_lists
    from public.nudge_data d, lateral jsonb_array_elements(coalesce(d.data->'lists','[]'::jsonb));
  select count(*) into blob_smart
    from public.nudge_data d, lateral jsonb_array_elements(coalesce(d.data->'smartLists','[]'::jsonb));

  select count(*) into row_reminders from public.reminders   where deleted_at is null;
  select count(*) into row_lists     from public.lists       where deleted_at is null;
  select count(*) into row_smart     from public.smart_lists where deleted_at is null;

  if row_reminders <> blob_reminders then
    raise exception 'reminders: blob has %, table has % — STOP', blob_reminders, row_reminders;
  end if;
  if row_lists <> blob_lists then
    raise exception 'lists: blob has %, table has % — STOP', blob_lists, row_lists;
  end if;
  if row_smart <> blob_smart then
    raise exception 'smart_lists: blob has %, table has % — STOP', blob_smart, row_smart;
  end if;

  raise notice 'OK: % reminders, % lists, % smart lists', row_reminders, row_lists, row_smart;
end $$;

-- Every row must carry a comparable, canonical stamp. A malformed one would sort wrongly
-- against every other stamp and could make an item unreachable by the delta cursor.
select count(*) as bad_stamps
from public.reminders
where updated_at !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$';   -- expect 0

-- Spot-check a few payloads against the blob before trusting the migration.
select id, updated_at, data->>'title' as title
from public.reminders order by updated_at desc limit 5;
