# Nudge — reminders that don't get forgotten

A reminders app built around one problem: **overdue items pile up, get buried, and get ignored.**
Nudge fixes that with fast capture, a pinned overdue section that never scrolls away, and a
3-stage guided triage to clear the backlog.

Built for Noah. Phase 1 = web app (this folder). iOS native + widgets come later.

---

## Run locally

```bash
cd nudge
python3 -m http.server 8910
# open http://localhost:8910
```

It's a single `index.html` — no build step, no dependencies. Works offline (localStorage).

## Deploy (like StudyTrack)

Push this folder to a GitHub repo with Pages enabled, or drop it on any static host
(Netlify, Vercel, GitHub Pages). It's a PWA — on iPhone, open in Safari → Share →
**Add to Home Screen** for a full-screen app with its own icon.

---

## Enable cloud sync (cross-device)

Right now data lives in your browser (localStorage). To sync across iPhone + web:

1. Create a **new** Supabase project (free tier is fine) — separate from StudyTrack & Finance.
2. In the SQL editor, run:

   ```sql
   create table nudge_data (
     user_key text primary key,
     data jsonb,
     updated_at timestamptz default now()
   );
   alter table nudge_data enable row level security;
   create policy "anon all" on nudge_data for all
     using (true) with check (true);
   ```

3. In `index.html`, find the `SUPABASE` config near the top of the `<script>` and paste your
   Project URL + anon public key:

   ```js
   const SUPABASE = {
     url:  'https://YOURPROJECT.supabase.co',
     anon: 'YOUR-ANON-KEY',
     userKey: 'nudge-noah-2026'
   };
   ```

That's it — the storage layer auto-detects the keys and starts syncing. The sync pill in the
sidebar shows **Synced / Syncing / Local only**.

---

## Features (Phase 1)

- **Quick capture** — FAB / `N` key opens a one-field add sheet. Title only; date, list,
  priority, repeat, notes are all optional.
- **4 sections** — Overdue (pinned, coral) · Today · Upcoming · No Date.
- **Lists** — Reminders, Shopping, Claude, Study, Finance, Work, Personal + custom (color-coded).
- **3-stage triage** (the core fix):
  1. *Still relevant?* — one-at-a-time yes/no sweep to bin dead weight fast.
  2. *Clear the stale pile* — batch-dismiss everything 2+ weeks old in one tap.
  3. *Decide on the rest* — spotlight each keeper: Done / Reschedule / Delete.
- **Recurrence** — daily / weekly / monthly / yearly (auto-creates the next occurrence on complete).
- **Search**, **undo** on complete/delete, **PWA offline**, in-app escalating nudges.

### Keyboard shortcuts
`N` new · `/` search · `T` triage · `Esc` close

---

## Roadmap

- **Phase 2** — auto-reminders from Finance (savings goals, one-off expenses) & StudyTrack
  (milestones, subjects falling behind), tagged `[Auto]`. Background push via GitHub Actions.
- **Phase 3** — native iOS app (Swift), two-way Apple Reminders sync via EventKit, CloudKit.
- **Phase 4** — Scriptable widgets: overdue count, today's list, lock-screen badge.
