# Nudge — Tsuji Action Banner (feature spec)

**Written:** 29 Oct 2026, in Noah's "Tsuji Culinary School Plan" Claude project
**Status:** Agreed with Noah, not built yet
**For:** the Claude that builds Nudge. This file is self-contained. You do not need any other Tsuji documents.

---

## 1. What this feature does

Noah keeps the dates for his culinary school plan in an Apple Calendar (iCloud) calendar named **Tsuji Plan**. It has 24 events. **13 of them are tasks he must do** (register for a test, send an application, ask his school for a document). The other 11 are appointments or milestones and are out of scope.

Nudge shows the 13 tasks in a **banner** that appears only when something is due soon or overdue. Noah clears a task only by **typing a confirmation phrase**. A tap or swipe must never clear one. When he clears a task, Nudge marks the calendar event as **COMPLETED** and removes its Calendar alerts.

Dates and titles always come **live from the calendar**. When Noah or Claude changes a date in Calendar (many are estimates), Nudge follows automatically. Only the event IDs are hardcoded.

---

## 2. The 13 action events

Every event below is an **all-day** event in the calendar **Tsuji Plan**. Titles and dates are their state on 29 Oct 2026, verified from a Calendar export. They may change. **The UID will not.**

| # | UID (hardcode exactly) | Date (start) | Current title |
|---|---|---|---|
| 1 | `tsuji-plan-24-20261029@noah.flouty.uk` | 2027-01-09 | Check open campus entry pass (参加証) has arrived |
| 2 | `tsuji-plan-02-20261027@noah.flouty.uk` | 2027-01-31 | Japanese study checkpoint 1 – timed practice test |
| 3 | `tsuji-plan-03-20261027@noah.flouty.uk` | 2027-03-15 | Check JLPT July registration has opened (estimate) |
| 4 | `tsuji-plan-04-20261027@noah.flouty.uk` | 2027-04-30 | Japanese study checkpoint 2 – timed practice test |
| 5 | `tsuji-plan-21-20261029@noah.flouty.uk` | 2027-08-15 | Register for December JLPT – opens mid/late Aug (estimate) |
| 6 | `tsuji-plan-07-20261027@noah.flouty.uk` | 2027-09-01 | Start kitchen job search |
| 7 | `tsuji-plan-12-20261027@noah.flouty.uk` | 2027-12-01 | Check if Tsuji 2029 入学要項 is published (estimate) |
| 8 | `tsuji-plan-22-20261029@noah.flouty.uk` | 2028-03-15 | Register for July JLPT – opens mid/late Mar (estimate) |
| 9 | `tsuji-plan-14-20261027@noah.flouty.uk` | 2028-08-01 | Ask TIHS for graduation certificate |
| 10 | `tsuji-plan-23-20261029@noah.flouty.uk` | 2028-08-15 | Register for December JLPT – opens mid/late Aug (estimate) |
| 11 | `tsuji-plan-15-20261027@noah.flouty.uk` | 2028-09-01 | Tsuji eligibility screening applications open (estimate) |
| 12 | `tsuji-plan-16-20261027@noah.flouty.uk` | 2028-10-15 | Create Tsuji online application account + take ID photo |
| 13 | `tsuji-plan-17-20261027@noah.flouty.uk` | 2028-11-01 (to 11-07) | Tsuji general exam – round 1 window (estimate) |

Notes:
- **The date suffix matters.** UIDs 21–24 end in `20261029`; the rest end in `20261027`. Copy them exactly.
- #13 is a multi-day all-day event (1–7 Nov 2028). Its **due date is the start date**: the plan is to apply on day one.
- Keep the 13 UIDs in **one constant** in the code. Claude may later give Noah new action events to add, in the same format `tsuji-plan-NN-YYYYMMDD@noah.flouty.uk`.

**Never touch the other 11 events** in Tsuji Plan: UIDs 01, 05, 06, 08, 09, 10, 11, 13, 18, 19, 20. **UID 01** (the 16 Jan 2027 open campus) has an **invitee** (Noah's mum). Editing it would send her an update.

---

## 3. Finding the events (EventKit)

- **Access level.** Nudge needs **full access** to events. Write-only access cannot read existing events. Per Apple, with write-only access "a request for a list of calendars returns a single virtual calendar … Requests for events on the virtual calendar return no results." Full access allows reading and editing. Source: https://developer.apple.com/documentation/eventkit/accessing-the-event-store
- **Matching.** Match on `calendarItemExternalIdentifier` against the UIDs above. Apple says this identifier "allows you to access the same event or reminder across multiple devices." Do **not** use `eventIdentifier` or `calendarItemIdentifier`: they are local to one device and can change. Source: https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier
- **Unverified (Test 0 settles it).** The export proved Calendar kept these UIDs. It has **not** yet been checked that EventKit returns them as `calendarItemExternalIdentifier` for this iCloud calendar. Apple only says the value is "as provided by the calendar server". **If Test 0 fails, stop and report to Noah. Do not invent another matching method.**
- **Only search the Tsuji Plan calendar.** Apple notes duplicates can exist, for example when "a calendar item was imported from an ICS file into multiple calendars". Find the calendar by title once, store its `calendarIdentifier`, and fall back to the title if that ID stops working. If one UID matches more than one event in Tsuji Plan, show an error row for it instead of guessing.
- **Date range.** `predicateForEvents(withStart:end:calendars:)` "matches only those events within a four-year time span. If the date range … is greater than four years, it's shortened to the first four years." Search from **today − 1 year to today + 3 years**. That covers every event through 2028 and keeps overdue items visible. Source: https://developer.apple.com/documentation/eventkit/ekeventstore/predicateforevents(withstart:end:calendars:)
- **When to re-read.** On launch, when the app comes to the foreground, and on `EKEventStoreChanged`.

---

## 4. Status of each item

Work out "today" and every date as **calendar dates in the device's current time zone** (Noah is in Asia/Tokyo). All-day events have no time zone of their own. Do not compare UTC timestamps.

| Status | Rule |
|---|---|
| **Cleared** | The event title starts with `COMPLETED` (case-insensitive, after trimming spaces) |
| **Overdue** | Not cleared, and today is after the due date |
| **Due soon** | Not cleared, and the due date is today to today + 7 days (inclusive) |
| **Later** | Not cleared, due date more than 7 days away |
| **Missing** | UID not found in Tsuji Plan |

Nudge stores the last known title and date for each UID so a "Missing" row can still show what it was.

---

## 5. Banner

- **Visibility.** Show the banner **only** if at least one item is Overdue, Due soon or Missing. Otherwise it does not appear at all.
- **Section "Now":** Missing items first, then Overdue (oldest first), then Due soon (soonest first).
- **Section "Next steps":** the next **3** "Later" items, soonest first.
- **Each row:** title, date, and "today", "in N days" or "N days overdue". Tapping a row opens the details (the event notes), or the event in Calendar.
- **Collapse.** Noah can collapse the banner while he works on something. Collapsing never clears anything. It stays collapsed until he expands it, or until a new item enters "Now"; then it expands again.

---

## 6. Clearing an item (typed confirmation)

1. The row has a **Clear** button. It opens a sheet with a text field.
2. Noah must type exactly **`Confirmed and completed`**. The match is case-sensitive; spaces at either end are ignored. The confirm button stays disabled until the text matches.
3. **There is no other way to clear an item.** No swipe, long-press or tick box.

When he confirms:

1. **Check the guardrails.** All must pass, or no calendar edit happens and an error is shown:
   - the UID is one of the 13
   - the event is in Tsuji Plan
   - `event.hasAttendees == false`
   - the calendar allows content modifications
2. **Save a local backup** for this UID: the original title, the original alarms (each `relativeOffset` or `absoluteDate`) and the completion date.
3. **Edit the event** and save with span `.thisEvent`:
   - Title: `COMPLETED – ` + original title. Add the prefix **only if** the title doesn't already start with `COMPLETED`.
   - Notes: append a new line `Completed in Nudge on YYYY-MM-DD` (local date).
   - Alarms: remove all alarms on the event.
4. **Cancel all pending Nudge notifications** for this UID.
5. **If saving fails** (offline, permission revoked): keep the item cleared locally, show "Calendar not updated yet", and retry on the next launch or store change.

**Check during Test 3.** Calendar shows a default all-day alert ("1 day before at 09:00 (default)") that comes from Noah's Calendar settings, not from the event. It may not appear as an `EKAlarm` on the event, in which case Nudge cannot remove it. Report what you find; don't try to change Calendar settings.

---

## 7. Source of truth and undo

**The Calendar title decides.** Nudge's local store is only a cache and backup.

- **Title starts with COMPLETED, but Nudge thinks it's open** (Noah typed it in Calendar, cleared it on another device, or Nudge lost its data): treat it as cleared and cancel notifications. Don't touch alarms unless a local backup exists.
- **Title no longer starts with COMPLETED, but Nudge thinks it's cleared** (Noah deleted the prefix in Calendar = **undo**):
  - mark the item open again
  - restore the alarms from the local backup, if this device has one
  - append `Reopened in Nudge on YYYY-MM-DD` to the notes
  - reschedule notifications
- **More than one device:** if Nudge runs on both Mac and iPhone, the title keeps them in step. The alarm backup exists only on the device that cleared the item, so an undo on the other device can't restore alarms. Show a small note when that happens.

---

## 8. Notifications

- For each open item: a local notification at **09:00 local time on the due date**, then **every day at 09:00** until it's cleared.
- Example wording: "Tsuji: <title> — due today" / "Tsuji: <title> — 3 days overdue".
- Reschedule when a date changes in Calendar. Cancel on clear.
- Calendar's own alerts on the event keep firing until the item is cleared (Noah wants both). Clearing removes them (section 6).
- Stay within iOS's limit on pending local notifications. With 13 items, scheduling about 7 days ahead and topping up on each launch is enough.

---

## 9. Never do

- Edit, move or delete any event whose UID is not in the list of 13.
- Change an event's date, calendar or recurrence, or delete it.
- Edit any event with attendees.
- Create new calendar events.
- Clear an item without the exact typed phrase.
- Change Calendar app settings.

---

## 10. Tests, in order

Build a **debug "today" override** so the date-based tests can run now.

| # | Test | Pass if |
|---|---|---|
| **0** | **Read-only ID check.** List every event in Tsuji Plan with its `calendarItemExternalIdentifier`, title and date. | All 13 UIDs found, exactly once each, with the titles and dates in section 2. The 11 others are found and ignored. **If this fails, stop and report to Noah.** |
| 1 | Today = 2026-10-29 | Banner hidden |
| 2 | Today = 2027-01-03 | Banner shows. Now: #1 (9 Jan, in 6 days). Next steps: #2, #3, #4 |
| 3 | Today = 2027-01-12 | Now: #1 "3 days overdue" |
| 4 | Typing gate | "confirmed and completed", "Confirmed", and an empty field cannot clear |
| 5 | Clear #1 (real event, 9 Jan) | In Calendar: title "COMPLETED – Check open campus entry pass…", note line added, alerts gone (report whether the default alert remains). Notifications for #1 cancelled. Still cleared after restarting Nudge |
| 6 | Undo #1: delete "COMPLETED – " from the title in Calendar | Item back in Nudge, alerts restored, "Reopened…" line added, notifications rescheduled. **#1 must end this test exactly as it started, apart from the two note lines** |
| 7 | Change #1's date in Calendar to 10 Jan, then back to 9 Jan | Banner and notifications follow both changes |
| 8 | Missing: add a fake UID to the list (debug build only) | A "Missing from calendar" row appears; no crash |
| 9 | Guardrail: add UID 01 (has an invitee) to the list (debug build only), then try to clear it | Nudge refuses to edit it. **Remove UID 01 from the list before release** |
| 10 | Calendar access off | Clear error message; nothing crashes; nothing is cleared |

---

## 11. Choices Claude made that Noah hasn't confirmed yet

Noah should confirm these or change them before or during the build:

1. The phrase match is **case-sensitive**.
2. Collapse behaviour (section 5): stays collapsed until expanded or until a new "Now" item appears.
3. Due date = **start date**, including the multi-day round 1 window.
4. On undo, Nudge **adds** a "Reopened" line instead of deleting the "Completed" line.
5. The title prefix is exactly `COMPLETED – ` (with an en dash). Detection accepts any title starting with "COMPLETED".
6. A "Missing" item can still be cleared with the phrase. That clears it in Nudge only; no calendar edit.
