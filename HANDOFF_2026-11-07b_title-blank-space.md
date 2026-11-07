# Handoff — 2026-11-07b — blank space under the title (iPhone)

Status: committed in Cowork; Claude Code reinstalls + pushes. Prompt: CLAUDE_CODE_PROMPT_2026-11-07b_title-blank-space.md.

Symptom: existing reminder opens with empty lines under the title (1 to ~6), iPhone only; tapping the title clears it.
Checked: titles are trimmed on every save path (AddReminderView, QuickCatch, Scan all go through saveReminder) → not stored newlines. Title is set in onAppear during the sheet animation → vertical TextField mis-measures at mid-animation width.
Fix: `.id(titleLayoutKey)` on the title TextField, bumped once 0.5 s after load() for EDITING only, skipped if the title is already focused.
Not changed: notes field (Noah doesn't use notes; same fix can be applied if it shows the same symptom). Double-tap gesture code untouched (see nudge-title-doubletap-race memory — unrelated, unsolved).
If it still happens: try a later bump (e.g. 0.8 s) or a second bump, and test 10× per reminder, reporting a hit rate.
