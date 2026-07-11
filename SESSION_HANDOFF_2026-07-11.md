# Nudge — Session Handoff (2026-07-11, Cowork)

Bookkeeping/verification session. No code shipped. Reconciled which fable-audit bugs are
actually fixed, closed out D2, and ran the D1 migration audit. Repo HEAD unchanged at `5de79fb`
except a committed doc fix to `SECURITY_D2_RUNBOOK.md`.

---

## 1. D2 (secrets-in-client / Supabase Auth + RLS) — CLOSED

Everything is done. Confirmed this session:

- **Both clients signed in and SYNCING** — iPhone + Mac on the cloud sync path. Noah confirmed
  sync is working (a change on one device lands on the other).
- **Part B (iOS + widget Swift migration) SHIPPED** in `42053ca` — verified by inspecting the
  commit: `AuthStore.swift` (Keychain shared access group `FMF6YAVA23.uk.flouty.Nudge.shared`,
  not UserDefaults), `Auth.swift` (email OTP-code flow), `NudgeStore.swift` refresh()/push()
  gated on isAuthed, `WidgetData.swift` reads shared Keychain, `SyncSettingsView.swift` sign-in
  UI, `Secrets.swift` (anon key, gitignored — only `.template` committed), userKey dropped
  everywhere. Also fixed: push() never checked HTTP status.
- **Supabase email template fixed** with `{{ .Token }}` — OTP code now arrives (Noah did this).
- **Anon key rotation — NOT required.** RLS neutralized the leaked keys (negative test returns
  `[]`). Rotation is pure hygiene. The older docs calling it "mandatory" were stale (pre-RLS).
  Simplest cleanup instead: delete `config.js` (web app retired, nothing loads it). NOTE:
  `config.js` is COMMITTED, not gitignored, despite older doc claims — now corrected in the runbook.

## 2. D1 (per-item sync) migration audit — DONE, effectively PASS

Ran `supabase/d1/03_verify.sql` against the Nudge project. It raised:

```
reminders: blob has 195, table has 193 — STOP
```

Investigated the 2 "missing" rows (read-only query against the blob). They are:

- `auto-fin-goals-2026-06` — "💰 Savings check-in — 0% to your goals"
- `auto-fin-oneoff-o09721755-026` — "💰 Budget for Bed - Send to Mum (¥22,000)"

**These are NOT data loss.** They are finance auto-reminder STUBS: `auto-fin-*` ids,
💰-prefixed, `updatedAt = NULL`. They dropped correctly during migration because a mergeable
per-item row requires a non-null `updatedAt`. Finance auto-reminders are gated OFF at the source
and **Noah does not want them.**

So the migration lost nothing real. The correct expected count is **193 real reminders, not 195.**

**Decision (Noah, 2026-07-11): leave the 2 stubs in the blob. Do NOT write to the blob to remove
them** — not worth any risk to production data for rows that are already absent from the live apps.
They get deleted wholesale when `nudge_data` is retired (`05_retire_nudge_data.sql`) after the
rollback window (~2026-07-24). The calendar cleans them up at zero risk.

**Known caveat:** `03_verify.sql` hard-asserts `blob count == table count`, so it will always
"fail" the count assertion while any auto-fin / null-`updatedAt` stub sits in the blob. Everything
else in the script passed (bad_stamps, spot-check). Treat 193 as the pass number.

## 3. Repo doc fix committed

`SECURITY_D2_RUNBOOK.md` — corrected two stale claims (config.js is committed not gitignored;
anon rotation is optional not mandatory). Committed + pushed by Noah via Claude Code this session.

---

## 4. What's left (whole project) — 2 items, both device tests, NO deadline

- **Geofencing** (shipped `4bb5249`, compiles both targets, runtime-UNVERIFIED). Needs a real
  iPhone walk test: quit the app, cross a real 150m boundary, confirm the reminder fires. Also
  untested: grant/deny permission paths, arrive-vs-leave, the 20-region cap. This is the whole
  point of the feature and the only way to prove app-closed firing works.
- **S3** (snooze/early-alert fix, shipped `7523222`, build-verified only). Needs: snooze a
  routine, wait 30 min, confirm the early alert reschedules. Narrowest impact (only routines).

## 5. Optional / no action needed

- Delete `config.js` whenever convenient (web retired). Not urgent.
- `nudge_data` retirement + tombstone purge (`04`/`05` scripts) after ~2026-07-24 — this also
  removes the 2 finance stubs.
- Old rollback backup `~/Nudge_backups/manual_2026-07-10_1052/` can lapse after the 24th — D1
  is verified, nothing to recover.

## 6. Project rules (unchanged)
- Confirm understanding before building; ask if <100% sure. Safety & security first.
- Never ask Noah to paste keys/API keys into chat.
- Cowork cannot commit to this `.git` — commits via Claude Code. Clear stale locks with:
  `rm -f .git/index.lock .git/refs/heads/*.lock .git/HEAD.lock 2>/dev/null; true`
- Web app is retired — iOS + Mac only.
