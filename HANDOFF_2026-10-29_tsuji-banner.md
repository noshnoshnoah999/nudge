# Handoff — 2026-10-29: Tsuji Action Banner, step 1 (Test 0)

The spec is `TSUJI_ACTION_BANNER_SPEC.md` in the repo root (Noah's upload, unchanged).
This file records **Noah's decisions on top of the spec** and where the build stands.
Where this file and the spec disagree, **this file wins**.

## Noah's decisions (29 Oct 2026)

1. **Banner placement:** on both the **Home** tab and the **Today** tab, on **iPhone and Mac**.
2. **Notifications from both devices.** Noah accepts duplicates (Nudge on iPhone + Nudge on Mac,
   plus Calendar's own alert on each device = up to 4 alerts per item on the due day).
   Apple Reminders sync is OFF (since Oct 2026), so no Apple Reminders alerts are involved.
3. **Notification schedule:** as the spec says — 09:00 local on the due date, then daily at 09:00
   until cleared — scheduled **7 days ahead**, topped up on launch.
   - **Still to confirm with Noah:** Nudge keeps only the 64 soonest pending notifications
     (`Notifications.swift`, line ~162). Proposed rule: if slots run short, drop Tsuji's
     furthest-out days first, never normal reminders. Ask before building step 2.
4. **Settings → "Tsuji plan" list** showing all 13 items and their status, so Noah can see the
   plan when the banner is hidden (the banner stays hidden until 2 Jan 2027).
5. **Fix 1 — test tools behind a separate switch, not "debug build only".** `reinstall_nudge.sh`
   installs the **Debug** build on both iPhone and Mac, so `#if DEBUG` is Noah's everyday app.
   The "today" override, the fake UID (Test 8) and UID 01 (Test 9) go behind a hidden Test
   switch that is **off by default**, and the switch is removed after testing.
6. **Fix 2 — Test 9 can't reach Noah's mum.** The guardrail is a plain function on values
   (UID in the 13? in Tsuji Plan? hasAttendees? calendar editable?) tested with made-up values.
   When Test 9 uses the real UID 01 event, **Calendar saving is switched off in code** for that
   build. UID 01 is never in the list of a build that can save.
7. **Section 11 of the spec: all six choices approved as written** (case-sensitive phrase;
   collapse behaviour; due date = start date; undo adds a "Reopened" line; prefix
   `COMPLETED – ` with en dash, detection accepts any "COMPLETED" start; a Missing item can be
   cleared in Nudge only).
8. **The clear sheet must show the phrase on screen**, e.g. "Type **Confirmed and completed**
   to clear this item." It is a confirmation, not a memory test. Autocorrect off on the field.

## Build order

1. **Step 1 — Test 0, read-only (THIS SESSION, written, not built).**
2. Step 2 — banner, status logic, Settings list, notifications, typed clear, guardrails, with
   **Calendar saving switched off**. Tests 1–4, 8, 9, 10.
3. Step 3 — saving switched on. Tests 5–7 on event #1. Noah keeps his Calendar export as a
   backup before this step.

Each step: code written in the Nudge project chat, then a Claude Code prompt to build,
install, push and clear stale locks.

## Step 1 — what was written

| File | What |
|---|---|
| `ios/Nudge/Nudge/TsujiPlan.swift` (new) | The one constant: calendar title + the 13 action UIDs, generated from the spec table |
| `ios/Nudge/Nudge/TsujiIDCheckView.swift` (new) | Read-only Test 0 screen + report |
| `ios/Nudge/Nudge/SyncSettingsView.swift` | New "Tsuji plan" section (after Overdue) linking to the check |

`Nudge/` is a synchronized folder group, so no pbxproj edit is needed.

**What the check reports:** access level; calendars named "Tsuji Plan" (count, account, type,
editable); every event in Tsuji Plan in a today−1y window (4 years minus a day, to stay under
EventKit's four-year cap); for each of the 13 UIDs: found count, start/end date and title vs the
spec, all-day, invitees (yes/no only), repeats, alarms on the event; the 11 other events; a
**safety check that UID 01 reports invitees** (if it doesn't, the hasAttendees guardrail can't
protect it and step 2 needs rethinking); copies of the 13 UIDs in other calendars.

**Safety:** the check has its own EKEventStore and calls only read APIs. Verified before
writing: no `save`/`remove`/alarm/title/notes writes in either new file, none of the 11
non-action UIDs in the list, all 13 UIDs/dates/titles match the spec byte for byte.

## Next

1. Claude Code builds and installs (prompt: `CLAUDE_CODE_PROMPT_2026-10-29_tsuji-step1.md`).
2. Noah opens **Settings → Tsuji plan → Calendar ID check** on **both iPhone and Mac**, taps
   **Copy report**, and pastes both reports into the Nudge project chat.
3. If Test 0 fails: **stop**, report to Noah, do not invent another matching method.
4. If it passes: confirm decision 3's notification-slot rule, then write step 2.

Also record from the report for step 3: whether the "1 day before at 09:00 (default)" alert
shows up as an EKAlarm on the events (spec section 6 note).
