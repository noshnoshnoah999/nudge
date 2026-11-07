# Claude Code prompt — 2026-11-07b — title blank space + search keyboard lag (iPhone)

Paste everything below the line into Claude Code, opened in the Nudge repo.

---

Cowork has already written AND committed BOTH changes below. Your job is ONLY: reinstall, push, clean up locks. Do not edit or commit any code.

## SAFETY RULES (read first)
- Do NOT run `git checkout`, `git restore`, `git stash`, `git clean`, `git reset`, `git commit` or `git add`.
- Do NOT edit any file. If the build fails, STOP and report the exact compiler error to Noah — Cowork will fix it.

## What's in the commits (for context only)
`AddReminderView.swift`: the title TextField gets `.id(titleLayoutKey)`, bumped once 0.5 s after an EXISTING reminder's sheet opens (skipped if the title is already focused), so iOS re-measures the field at its real width. Fixes empty lines under the title on iPhone.

`ContentView.swift`: the Search text field gets a `@FocusState searchFocused`; `switchTab` sets it false BEFORE the animated tab switch, so the keyboard closes immediately instead of after the tab animation.

## Steps
1. `git status` (should be clean) and `git log --oneline -5` — confirm these commits sit on top of `609a3d7`: `d5d0d85` (title fix), `496a96c` (docs), `e476540` (search keyboard), plus a final "Docs:" commit updating this prompt.
2. Install with `reinstall_nudge.sh` (builds iOS + Mac). Confirm the REAL iPhone install result from the device install output, not just the script's summary line, then the Mac.
3. `git push`.
4. Remove stale git locks (`.git/*.lock`, any `*.lock` under `.git/`) ONLY if `pgrep -fl git` shows no git process running.
5. Report: build result, iPhone + Mac install result, push result.

## Tests for Noah (iPhone)
Search: type something, tap the X, then tap Home / Overdue — the keyboard should start closing the moment you tap. Also try without tapping X first.

Title:
Open "Send Lara VJW QR Code | Double Check Passport Number" 10 times and "FaceTime Dad" 10 times. Count how often the blank space is still there once the sheet has finished opening (a quick snap to the right height at ~0.5 s is expected). Pass = 0/20.
