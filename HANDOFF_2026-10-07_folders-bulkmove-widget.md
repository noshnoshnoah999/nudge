# Nudge handoff — 2026-10-07: widget alerts, Select All, bulk-move times, Folders

Written in Cowork. **Nothing here has been compiled yet** (no Swift toolchain in Cowork).
All four features are committed locally on `main`, one commit each, not pushed.

| Commit | Feature |
|---|---|
| `142b06d` | Widget completion cancels that occurrence's notification + urgent alarm |
| `20fd980` | Multi-select: Select All / Deselect All |
| `a84ed09` | Bulk move: per-reminder times + Auto-arrange with preview |
| `457c7ee` | Folders |

`ios/Nudge/Nudge.xcodeproj/project.pbxproj` has a 1-line uncommitted change that predates
this session (it moves the RecurrenceEngine.swift file reference line). Noah said **leave it**.

---

## 1. Widget completion → no notification afterwards (`142b06d`)

**Problem:** completing early from the iPhone widget wrote to Supabase only. The pending
local notification lived in the *app's* notification centre, which the widget extension
can't reach, so it still fired unless Nudge was opened first.

**Fix:** `CompleteReminderWidgetIntent` now conforms to `LiveActivityIntent` (iOS only, via
an extension at the bottom of the file). Apple's WidgetKit docs (*Adding interactivity to
widgets and Live Activities*) say that for an intent conforming to `LiveActivityIntent`
"the system performs the app intent in the app's process", launching Nudge in the
background if needed. After a **successful** completion write:

- `WidgetLocalAlerts.clear` removes pending and delivered `nudge-<id>` and `nudge-<id>~e*`
  notifications, and cancels the AlarmKit alarm (`NudgeAlarmID.uuid`, moved to
  `Shared/NudgeAlarm.swift`; the algorithm is unchanged).
- `WidgetCompletionLedger` (UserDefaults, 3-day TTL, keyed by id + completed due date):
  `NotificationManager.reschedule()` skips a reminder whose current due date is still the
  completed one. This stops a stale in-memory store from putting the notification back.
- It posts `nudgeWidgetCompleted`. `NudgeStore` observes that, then runs `refresh()` +
  `NotificationManager.shared.reschedule()`, so a repeating reminder's next occurrence gets
  its notification while the app is running.
- If the write fails, nothing is cancelled.

**Known limit:** if Nudge was fully killed, the next occurrence's notification for a
repeating reminder is scheduled on the next app open (pre-existing behaviour).

**Risk to check on device:** whether the background launch from the widget works on a
free Apple team / with no `NSSupportsLiveActivities` key. If widget taps stop working at
all, revert just the `extension CompleteReminderWidgetIntent: LiveActivityIntent {}` line.

## 2. Select All / Deselect All (`20fd980`)

- The selection bar now shows for all of select mode. Move is disabled at 0 selected.
- Select All covers every reminder on the current tab (Today or Overdue), including
  collapsed AI-group members.
- Cancel became an `xmark` icon in the Folders commit, to make room.

## 3. Bulk move (`a84ed09`)

- Segmented control: **Keep times / One time / Set each** (per-row time pickers).
- **Auto-arrange times**, implemented by the pure `AutoArranger` in `BulkMoveView.swift`:
  - 07:45–19:30, 15 min apart, in on-screen order.
  - Avoids other open reminders on the target day, by at least 15 min.
  - Ignores the calendar.
- A preview sheet opens first. **Use these times** fills them into "Set each", then Move
  applies them.
- If they don't fit, an alert offers:
  - **Squeeze in:** the gap shrinks 15→1 until everything fits. The worst case ignores
    existing reminders.
  - **Spill to next day:** the extras go to the next day from 07:45, avoiding that day's
    reminders, rolling forward, capped at 14 days.
- Auto-arranged times skip the calendar-clash alert. Any manual edit re-enables it.
- The algorithm was checked with a Python port: 48 slots per day, correct jumps past
  existing times, and 60 items squeeze to an 11-min gap.

## 4. Folders (`457c7ee`)

- **Storage:**
  - `Folder {id, name, icon}` array under `"folders"` in the synced settings row.
    `NudgeStore.folders` is `@Published` and re-derived in `settings.didSet`.
  - Membership is `Reminder.folderIds: [String]?`.
  - No new table and no RLS change.
  - The settings row is last-write-wins as a whole, so simultaneous folder edits on two
    devices can lose one.
- **Store API:** `createFolder`, `updateFolder`, `deleteFolder` (strips the id from
  reminders only), `reorderFolders`, `moveFolder(_:onto:)`, `setFolderIds`,
  `addReminders(_:toFolder:)`, `removeReminders(_:fromFolder:)`, `memberFolders(of:)`.
- **`FolderViews.swift`** (new file; `Nudge/` is a synchronized group, so no pbxproj edit):
  - `FolderedSections` wraps Today, Overdue, each Upcoming section and Smart Collections.
    Folder sections follow folder order and are collapsible per page
    (`@AppStorage collapsedFolderSections`). Unfiled reminders sit at the bottom under
    "NOT IN A FOLDER". Pages with no foldered reminders render exactly as before.
  - Folder headers are `.draggable`/`.dropDestination`, so dragging one onto another
    reorders folders everywhere.
  - `FolderPickerSheet` is used by multi-select and by the long-press "Folders…" item.
    Adding a reminder that's already in another folder shows "Add anyway".
  - `FolderMembershipMenu` is the "Folders" row on the Add/Edit screen. It's written via
    `store.setFolderIds` after save.
  - `FolderEditorSheet` handles the name and the SF Symbol grid.
  - `FoldersManagerView` handles reorder handles, delete with confirmation, and edit.
  - `FolderContentsView` opens when you tap a folder on the Lists tab.
- **Not foldered, deliberately:**
  - The Home preview: a 6-item dashboard preview.
  - A list's own page (`FilteredListView`), which already has drag-and-drop sections.
  - The widget, as Noah asked.
- **Both devices must run this build:** an older build decodes `Reminder` without
  `folderIds` and drops it the next time it edits that reminder.

## Test checklist (Noah, on device)

1. Widget:
   - Make a one-off due in 5 min, complete it on the widget, don't open Nudge. No
     notification should arrive.
   - Repeat with Nudge force-quit.
   - Repeat with an Urgent (alarm) reminder.
2. Repeating reminder completed on the widget: this time's notification is gone, and the
   next one appears in the app.
3. Select mode on Today: Select All selects all, then Deselect All. Switching tab clears it.
4. Move 5 reminders → Auto-arrange → check the preview times → Use these times → Move.
5. Move 60 reminders (or temporarily fill a day) → check both overflow options.
6. Folders:
   - Create two folders.
   - Add a reminder to both and check the warning.
   - Check it appears under both on Today.
   - Collapse one.
   - Drag a header to reorder.
   - Delete a folder: the reminders must stay.
   - Check that the Mac shows the same folders after a sync.
