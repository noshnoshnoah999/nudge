# Prompt Template for Future Native App Builds

Use this when turning another app (StudyTrack, Finance, mum-shop, …) into a native iOS + Mac
app the way Nudge was built. Pair it with [NATIVE_APP_GUIDE.md](NATIVE_APP_GUIDE.md) (the full
technical reference). Copy the block below, fill in the bracketed sections, and paste it into
a fresh Claude Code session — it's self-contained, so a session with no Nudge context still
knows exactly what to do.

---

```
I'm building [StudyTrack / Finance] as a native iOS + Mac app following the Nudge architecture. I've read NATIVE_APP_GUIDE.md and understand the blob model, SwiftUI patterns, and the 7-day signing cycle.

**App name:** [StudyTrack / Finance]
**Core entities:** [Sessions / Expenses, with fields like...]
**Data size estimate:** ~[100 KB / 500 KB] for typical usage
**Special features:** [e.g., live timer widget, expense categories, recurring rules, etc.]
**Integrations:** [e.g., Apple Calendar, Apple Reminders, HomeKit, etc. — or none]

**Phase 1: Scaffolding & Models (if starting from scratch)**
- Create ios/[AppName]/ project with shared iOS + Mac Catalyst build.
- Models in Shared/: [list your core data types]
- Supabase: one table (user_key UUID primary key, data JSONB, updated_at). Anon key + a
  hardcoded per-user UUID (no login flow) — same pattern as Nudge.
- Minimal SwiftUI: ContentView + a simple list view to verify the blob syncs.

**Phase 2: Core UI & State**
- Build the main views (tab bar, list, detail, add sheet).
- [AppName]Store: @MainActor, handles fetch/persist, conflict resolution.
  - persist() debounced ~700ms; ALSO add persistNow() (awaited immediate push) for any
    background notification action, or the change is lost when iOS suspends the app.
  - Guard setSync() so it only publishes when the value changes (avoids re-render churn
    that drops keyboard focus in open edit sheets).
- Backup strategy: snapshot on launch + every sync, keep ~60, throttle to 1 per 10 min.
- Test on iPhone: make sure fields focus, scrolling is smooth, etc.

**Phase 3: Polish & Testing**
- Notifications: on [due date / specific time / recurring]. persistNow() on the action handler.
- App-lock (Face ID / passcode) with a single-prompt guard (no concurrent evaluatePolicy).
- Undo (single last-deleted item is enough; defer asset cleanup until the undo window passes).
- Widget (Home Screen + Lock Screen, if you want it) — read-only, use AppIntents for actions.
- Dark mode, theme customization, compact layout toggle.

**Testing checklist before I finish:**
- [ ] Compile clean on Mac Catalyst.
- [ ] Offline: app works with no network.
- [ ] Sync conflict: edit locally, pull remote version, verify un-pushed local edits aren't stomped.
- [ ] Backup/restore: corrupt the local blob, restore from backup, verify it works.
- [ ] Reinstall: run the script, both iPhone and Mac get the fresh build with a reset 7-day clock.
- [ ] Test on iPhone (required — don't skip, it catches bugs Mac hides).
- [ ] Notifications fire on time AND their Complete/Snooze action persists.
- [ ] If Face ID enabled: unlock flow is smooth, no glitches.

**I want to avoid these mistakes (learned the hard way on Nudge):**
- No vertical-axis TextFields in scrolling forms (use single-line, or force focus with a
  simultaneous tap gesture). They don't focus on iPhone though they work on Mac.
- Don't call FileManager.createDirectory on every access (use lazy var / static let).
- Don't set syncState on every poll if it hasn't changed (guard to prevent re-renders).
- Don't use per-card DragGestures (glitchy with ScrollView; use context menu / edit sheet).
- A background notification action MUST await an immediate push, or the change is lost and
  then overwritten by the next refresh().
- Face ID prompts must not run concurrently (one-at-a-time guard).
- Must test on iPhone, not just Mac Catalyst.

**After building, I'll:**
- Write a release guide (how to reinstall, reset the 7-day clock, re-add the Xcode account
  if signing fails, etc.).
- Document any app-specific gotchas.

Let me start: [describe what you want first, or ask me to begin with scaffolding].
```

---

## How to use

1. **Pick the app** you're converting (StudyTrack / Finance / mum-shop).
2. **Copy the block above**, replace every `[bracket]` with that app's specifics (entities, fields, features, integrations).
3. **Paste into a new Claude Code session.** It'll go Phase 1 → 2 → 3, the same path that worked for Nudge.
4. Keep the web PWA and the native app over **one shared Supabase blob** so they stay in sync (mirror any rule — e.g. payday dating — in both).

## What you already have

- **[NATIVE_APP_GUIDE.md](NATIVE_APP_GUIDE.md)** — full technical reference (architecture, patterns, every gotcha, deployment).
- **This file** — the reusable kickoff prompt.
- **Nudge source** (`ios/Nudge/`) — a working reference implementation to point at.
