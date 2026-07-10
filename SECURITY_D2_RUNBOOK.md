# D2 — Supabase Auth + RLS Runbook (Noah does these steps)

This is the part that actually secures your data. The code changes (web done, iOS/widget speced) are useless until RLS is on. **Do the dashboard steps yourself** — I never touch your Supabase console and never ask you to paste keys into chat.

Order matters. Do not rotate keys until the very end, after everything works.

---

## PROGRESS (updated 2026-07-10)

- [x] **Auth user created** — `noah@flouty.uk`, uid `5c8b57ab-2646-472d-9996-664c0758f71d`.
- [x] **Step 2 done** — `nudge_data` has `user_id` col, backfilled to the uid (195 reminders intact), unique index + not-null set.
- [x] **Step 3 done** — RLS enabled on `nudge_data`; 3 policies keyed to `auth.uid() = user_id`.
- [x] **Removed a bypass** — an old `ALL` policy `nudge owner only` keyed to the burned `user_key` was found and DROPPED. It would have let the leaked key keep full access.
- [x] **Negative test PASSED (live, from Noah's Mac)** — anon-key-only read of `nudge_data` returns `[]` / HTTP 200. Leaked creds can no longer read data.
- [x] **study_data** — RLS enabled, no policies (Nudge project). Dead data, anon fully denied.
- [x] **finance_data** — RLS enabled, no policies (finance project `ipjwpkqcuztahumijici`). Auto-reminders stay off; web handles that safely.
- [ ] **Deploy new web code + sign in** — until then the live app shows "local" (expected; old code only sends anon key which RLS now rejects).
- [ ] **iOS/widget** — Part B of D2_HANDOFF.md, in Claude Code/Xcode.
- [ ] **Rotate anon keys** — Step 5 below. Lower urgency now RLS neutralizes them, but they're in git history → still rotate. Do AFTER deploy+sync confirmed.

---

## Honest framing (read first)

- A client-side app cannot hide a credential it uses. The anon key is *designed* to be public — but only becomes safe once **Row Level Security (RLS)** means the anon key grants nothing without a signed-in session. That's what these steps set up.
- Your current anon keys AND the old `user_key` row secrets are in git history. Treat them as **burned**. Rotating the anon keys (last step) is mandatory, not optional.
- Until Step 4 is verified live, **do not host the web app anywhere public.**

---

## Step 1 — Create your Auth user (Nudge project)

Supabase dashboard → project `epaiazxcdcseijkhrncm` → **Authentication → Users → Add user → Send invitation** (or just sign in via the app's magic link once Step 4 is live and it creates the user). Use `noah@flouty.uk`.

Then **Authentication → Providers → Email**: make sure **Email** is enabled and "Confirm email" is on. Under **URL Configuration**, add your app's URL (e.g. `https://your-host/` and/or `http://localhost:...`) to **Redirect URLs**, or magic links won't return to the app.

## Step 2 — Add `user_id` to the tables

SQL editor, run for the Nudge project:

```sql
-- nudge_data: add owner column, default to the caller's auth uid
alter table public.nudge_data add column if not exists user_id uuid default auth.uid();

-- backfill your existing single row to YOUR uid (get it from Authentication → Users)
-- replace <YOUR_AUTH_UID> with the uuid shown for noah@flouty.uk
update public.nudge_data set user_id = '<YOUR_AUTH_UID>' where user_id is null;

-- enforce one row per user so upsert-on-conflict works
create unique index if not exists nudge_data_user_id_key on public.nudge_data (user_id);
alter table public.nudge_data alter column user_id set not null;
```

## Step 3 — Enable RLS + policies (Nudge project)

```sql
alter table public.nudge_data enable row level security;

create policy "own row select" on public.nudge_data
  for select using (auth.uid() = user_id);
create policy "own row insert" on public.nudge_data
  for insert with check (auth.uid() = user_id);
create policy "own row update" on public.nudge_data
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

Repeat Steps 2–3 for `study_data` if it's still in use (same project). If StudyTrack is dead (handoff says unlinked 2026-06-11), you can instead just `enable row level security` on `study_data` with NO policies — that denies all anon access, which is the safe default.

## Step 3b — Finance project (separate: `ipjwpkqcuztahumijici`)

Finance is a different project with different JWT signing keys, so your Nudge session token will NOT work there. Two choices:

- **If you want finance auto-reminders back:** create an Auth user in the finance project too, repeat Steps 1–3 on its `finance_data` table, and tell me — I'll wire a second (finance) login into the web app.
- **If you don't need them right now (default):** just run `alter table public.finance_data enable row level security;` with **no policies**. That locks the finance data down completely to anon access. The web app already fails safe (finance auto-reminders just return nothing). This is the safer default; do this unless you say otherwise.

## Step 4 — Verify LIVE before rotating anything

1. Deploy the new web files (`index.html`, `config.js` locally present, `sw.js`, `manifest.json`) — or run locally.
2. Open the app, go to Settings → Cloud sync → **Sign in**, enter your email, click the magic link in your inbox.
3. Confirm the app shows "Signed in as noah@flouty.uk" and sync status reaches "synced".
4. Confirm your reminders load. Edit one; confirm it persists after reload.
5. **Negative test (this proves RLS works):** in a private window with NO session, try to read the data via the anon key:
   ```
   curl "https://epaiazxcdcseijkhrncm.supabase.co/rest/v1/nudge_data?select=data" \
     -H "apikey: <CURRENT_ANON>" -H "Authorization: Bearer <CURRENT_ANON>"
   ```
   With RLS on, this must return `[]` (empty). If it returns your data, RLS is not correctly applied — STOP and fix before rotating.

## Step 5 — Rotate the anon keys (only after Step 4 passes)

Dashboard → **Project Settings → API → "Reset" / roll the anon (publishable) key**, for BOTH the Nudge and Finance projects. Then:

1. Paste the new anon keys into your local `config.js` (never commit it — it's gitignored).
2. Update the iOS/widget `anon` constant (Claude Code will have parameterized it; see the iOS spec).
3. Re-run the Step 4 negative test with the OLD key — it must now fail entirely.

## Step 6 — Drop the dead `user_key` columns (optional cleanup)

Once web + iOS both sync via Auth and you've confirmed nothing reads `user_key`:

```sql
alter table public.nudge_data drop column if exists user_key;
```

Keep a backup export first.

---

## What "done" looks like

- App requires sign-in to sync; local-only (never wipes) when signed out.
- Anon key alone returns `[]` from the REST API (Step 4 negative test).
- Old anon keys + `user_key`s rotated/dropped and treated as burned.
- Nothing secret remains in `index.html` or the Swift source (only in gitignored `config.js` and the iOS Keychain).
