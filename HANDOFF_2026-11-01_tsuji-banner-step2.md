# Handoff — 2026-11-01: Tsuji Action Banner, step 2 (Calendar saving OFF)

Read with: `TSUJI_ACTION_BANNER_SPEC.md` (the spec) and `HANDOFF_2026-10-29_tsuji-banner.md`
(Noah's earlier decisions). Where they differ, the newest handoff wins.

## Status

- Step 1 (Test 0): **PASSED on iPhone and Mac**, 1 Nov 2026 18:24/18:25. All 13 UIDs found once,
  dates and titles match, all-day, no invitees, no repeats; the 11 others found; UID 01 reports
  invitees on both devices; one Tsuji Plan calendar (iCloud, editable); no copies elsewhere.
  `calendarIdentifier` differs per device (expected — stored per device).
- Step 2: **written and committed (`93864bd`), not built yet.** Calendar saving is OFF
  (`TsujiPlan.calendarWritesEnabled = false`).
- Step 3: not started. Flips the switch, then Tests 5–7 on event #1.

## Decisions made 1 Nov 2026

1. Notification slots: if Nudge runs short of its 64, Tsuji's furthest-out days are dropped
   first, never normal reminders. **Yes.**
2. Undo restores the clearing device's alarms **minus exact duplicates** (Noah asked Claude to
   pick). Test 6 passes if the "7 days before 09:00" and "on the day 09:00" alerts come back.
3. Leave the UID 01 title ("Open Campus l") as it is.
4. Banner: Home directly under the birthday banners; Today at the very top.
5. Tapping a row opens Nudge's own read-only details sheet.
6. Test mode is a **visible** toggle in Settings → Tsuji plan, off by default, removed after step 3.

## Test 0 alarm finding (matters for step 3)

Every action event has 3 alarms. Same on both devices: −572400 s (7 days before at 09:00) and
+32400 s (on the day at 09:00). The third differs: iPhone +32400 s (a duplicate on-day alert),
Mac −54000 s (1 day before at 09:00). Most likely Apple's per-device default alert (sources:
SOGo bug 2895; Open-Xchange KB on Apple default alerts). Not yet confirmed against Noah's
Calendar settings. The default alert IS an EKAlarm on both devices, so clearing can remove it;
undo can't recreate it as a "default" alert.

## What step 2 adds

| File | What |
|---|---|
| `TsujiPlan.swift` | + `calendarWritesEnabled = false`, the phrase + matcher, COMPLETED prefix/detection, the pure guardrail function |
| `TsujiStore.swift` (new) | Reads Tsuji Plan by UID, status by calendar date, Now/Next steps, collapse, typed clear, Calendar-title-is-truth reconcile, undo with de-duplicated alarm restore, notification plan, safety self-test |
| `TsujiNotifications.swift` (new) | 09:00 on the due date then daily, 7 days ahead, only leftover slots (max 64), "tsuji-" ids |
| `TsujiViews.swift` (new) | Banner, details sheet, clear sheet (shows the phrase), Settings plan list, Test tools |
| `SyncSettingsView.swift` | Tsuji plan section: Plan, Calendar ID check, Test mode toggle, Test tools |
| `ContentView.swift` | `TsujiBanner()` on Home + Today; `TsujiStore.shared.reload()` on launch + foreground |
| `Notifications.swift` | `reschedule()` calls `TsujiNotifications.schedule` at the end |

### Safety design

- **One write path.** `TsujiStore.saveToCalendar` is the only `store.save` call. It re-checks the
  master switch and every guardrail on the event itself (UID in the 13, in Tsuji Plan, no
  invitees, calendar editable, not repeating) before saving.
- **Dry runs can't become real.** A clear made while saving is off is stored as `.dryRun`; once
  saving is on, dry-run clears are forgotten, never written.
- **Test entries only while saving is off.** The made-up UID and UID 01 can only appear when
  `calendarWritesEnabled == false`. UID 01 is not in `actionUIDs`.
- **No other way to clear.** No swipe, long-press, tick box or notification action. Tsuji
  notifications use "tsuji-" ids, which NotificationManager's tap/complete handlers ignore.
- **Notifications respect** Nudge's Notifications switch and the system permission.

## Noah's step 2 test checklist (iPhone; then a quick look on the Mac)

Setup: Nudge → gear → **Tsuji plan** → turn on **Test mode** → **Test tools**.

| # | Do | Pass if |
|---|---|---|
| S | Tap **Run safety self-test** | Top line says **ALL CHECKS PASSED** |
| 1 | Tap **29 Oct 2026 (Test 1)** | No Tsuji banner on Home or Today |
| 2 | Tap **3 Jan 2027 (Test 2)** | Banner shows. NOW: #1 open campus entry pass, "in 6 days". NEXT STEPS: #2, #3, #4 |
| 3 | Tap **12 Jan 2027 (Test 3)** | NOW: #1 "3 days overdue" |
| 4 | Banner → **Clear** on #1. Type `confirmed and completed`, then `Confirmed`, then clear the field | "Clear item" stays greyed out every time |
| 4b | Type `Confirmed and completed` → **Clear item** | "Cleared in Nudge only…" message; banner disappears; **Calendar unchanged** |
| 4c | Test tools → **Reset test clears** | #1 is back in the banner |
| 8 | Turn on **Add a made-up missing event** | A "Missing from calendar" row in NOW; no crash |
| 9 | Turn on **Add the open campus event…** → open it → Clear → type the phrase | Refused with "isn't one of the 13" and "has invitees"; **open campus event unchanged in Calendar** |
| N | With 12 Jan set: **Show scheduled Tsuji notifications** | "[TEST] Tsuji: … overdue" at 09:00 on the next real days. **Send a sample notification** → appears in ~5 s |
| 10 | iPhone Settings → Privacy & Security → Calendars → Nudge → **None**, then open Nudge | Banner says Calendar access is off; no crash. **Set it back to Full Access** after |
| Mac | Turn on Test mode on the Mac, pick 3 Jan 2027 | Same banner as Test 2 |
| End | **Reset test clears**, turn both test entries off, turn **Test mode OFF** (both devices) | Banner gone (nothing due until 2 Jan); "Show scheduled" shows none |

**Important:** Test mode is per device. If it's left on, Nudge sends "[TEST]" notifications at
09:00. Turn it off on both devices when finished.

## Next

1. Claude Code: build, install, push (`CLAUDE_CODE_PROMPT_2026-11-01_tsuji-step2.md`).
2. Noah runs the checklist above and reports results.
3. Step 3 only after Noah approves: flip `calendarWritesEnabled` to `true`, then Tests 5–7 on
   event #1 (Noah keeps his Calendar export as a backup first). Also confirm the default-alert
   explanation by checking Calendar's default all-day alert setting on each device.
