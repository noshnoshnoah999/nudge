# Handoff — 2026-11-12 — "See more" notification action (Mac)

## Goal (Noah's words, agreed)
An actual "See more" option in the notification Options menu on Mac, next to Snooze 1 hour and Reschedule, so a long reminder title can be read without opening Nudge.

## Decisions
- Mac only (iPhone has long-press expand).
- Only long titles get the button (>= 45 chars, `seeMoreMinLength`). Threshold chosen because the Mac banner cut "Update the changes to December's Budget - fixed expenses for LINE..." at ~65 chars.
- Normal notifications unchanged. Only the re-posted one (after tapping See more) carries the full title in the body, above notes/location.
- Re-post is silent, same id (replaces itself), keeps Complete/Snooze/Reschedule, drops See more.

## Why this design
A notification action cannot expand a banner in place (no API; expand is system-owned). Re-posting with the title in the body is the only reliable route. Notification Content Extensions are reported unreliable on Mac.

## Status
- Code committed `11611d6` (Cowork). Not yet built/installed/pushed — see the 2026-11-12 Claude Code prompt.

## Unknowns to check in testing
- Whether macOS also truncates long body text (very long titles may still be cut).
- Whether tapping a background action brings the Nudge window forward on Mac Catalyst (Noah unsure).
- Threshold 45 may need tuning.
