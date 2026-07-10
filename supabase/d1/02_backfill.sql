-- ===========================================================================
-- 2. BACKFILL  (re-runnable: `on conflict do nothing`)
-- ===========================================================================
-- Stamps are derived from each item's own `updatedAt`, falling back to the epoch. This
-- MUST match seedMigratedMeta() in CloudSync.swift exactly — it seeds each migrating
-- device's local stamps the same way, so local and cloud agree by construction and the
-- first launch pushes nothing. (An item with no updatedAt gets the epoch, meaning
-- "oldest possible": the first real edit from any device outranks it.)
--
-- Note this is NOT `coalesce(updatedAt, createdAt, epoch)`. Falling back to createdAt here
-- while the client falls back to the epoch would make every such cloud row look newer than
-- its local twin on first pull. Harmless in itself (the payloads are identical), but the
-- two sides must be kept in step if either is ever changed.

create or replace function pg_temp.nudge_stamp(v text) returns text language sql immutable as $$
  select coalesce(
    to_char((nullif(v,''))::timestamptz at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    '1970-01-01T00:00:00.000Z')
$$;

insert into public.reminders (user_id, id, data, updated_at, deleted_at)
select d.user_id, r->>'id', r, pg_temp.nudge_stamp(r->>'updatedAt'), null
from public.nudge_data d,
     lateral jsonb_array_elements(coalesce(d.data->'reminders', '[]'::jsonb)) r
where r->>'id' is not null
on conflict (user_id, id) do nothing;

insert into public.lists (user_id, id, data, updated_at, deleted_at)
select d.user_id, l->>'id', l, pg_temp.nudge_stamp(l->>'updatedAt'), null
from public.nudge_data d,
     lateral jsonb_array_elements(coalesce(d.data->'lists', '[]'::jsonb)) l
where l->>'id' is not null
on conflict (user_id, id) do nothing;

insert into public.smart_lists (user_id, id, data, updated_at, deleted_at)
select d.user_id, s->>'id', s, pg_temp.nudge_stamp(s->>'updatedAt'), null
from public.nudge_data d,
     lateral jsonb_array_elements(coalesce(d.data->'smartLists', '[]'::jsonb)) s
where s->>'id' is not null
on conflict (user_id, id) do nothing;

insert into public.settings (user_id, data, updated_at)
select d.user_id, d.data->'settings', '1970-01-01T00:00:00.000Z'
from public.nudge_data d
on conflict (user_id) do nothing;
