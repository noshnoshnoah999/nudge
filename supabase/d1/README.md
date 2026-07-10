# D1 — per-item sync migration

Moves Nudge off "one JSON blob in one row, last writer wins" and onto one cloud row per
reminder / list / smart list, each with a row timestamp and a `deleted_at` tombstone.

Design + as-built notes: `D1_SYNC_DESIGN_per-reminder-merge.md` (read **§11** — the sections
above it are the original design and are wrong in five places).

## Run these now, in order, before installing the new app build

Open the Supabase SQL editor, paste one file, run it, read the output, then move to the next.

| File | What it does | What you should see |
|---|---|---|
| `01_tables.sql` | Creates the 4 tables, RLS policies, indexes | A policy list: only `own_rows`, on exactly those 4 tables |
| `02_backfill.sql` | Explodes `nudge_data` into rows. Re-runnable | No errors |
| `03_verify.sql` | Count assertions vs the blob | `OK: 195 reminders, 9 lists, …`, `bad_stamps` = 0, five real-looking titles |

**If `03_verify.sql` raises, stop.** Don't rerun `02`. A shortfall almost certainly means
duplicate reminder ids inside the blob, silently swallowed by `on conflict do nothing` — worth
understanding before anything ships.

Then install the new app build on both devices and do the two-device delete test: delete a
reminder on the Mac, confirm it disappears on the iPhone **and stays gone on the Mac**.

## Do NOT run these yet

| File | When |
|---|---|
| `04_purge_tombstones.sql` | In a few weeks. Harmless but pointless until tombstones exist |
| `05_retire_nudge_data.sql` | Only after both devices have been healthy on the new build for ~2 weeks. This is your rollback path |

## Rollback

`01`–`03` only ever ADD tables. Not one byte of `nudge_data` is modified, and the previous app
build still reads it. To roll back at any point before `05`: reinstall the previous build.

If the new build is installed *before* `01`–`03` are run, it fails safe — every pull 404s, the
"never push before a successful pull" guard holds, so nothing is written and nothing is lost.
The app just sits in local-only "Offline". Run the SQL and it recovers on the next poll.
