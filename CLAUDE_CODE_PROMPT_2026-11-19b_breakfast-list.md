# Claude Code prompt — 2026-11-19b: Breakfast list (shared with Budget) — check, build, reinstall, push

Repo: `~/Claude/nudge`, branch `main`.

## Security rules (read first)

- **Never print, echo, log or paste any key.** `ios/Nudge/Shared/Secrets.swift` is gitignored and
  now also holds Budget's Supabase URL + publishable key (`budgetSupabaseURL`,
  `budgetPublishableKey`). Read it only through the script below, which never prints the values.
- **Never `git add` `Secrets.swift`.** Don't ask Noah for any key, token or password.
- Nudge must only talk to the `breakfast_list` table in Budget's project, never `finance_data`.
- The checks below are **read-only** (GET). Do not write to Budget's Supabase project.

## Before anything

```bash
cd ~/Claude/nudge
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log --oneline -5
```

**Do NOT run `git checkout`, `git restore`, `git stash`, `git clean` or `git reset`.** If there are
uncommitted changes you didn't make, leave them alone and tell Noah.

## State of play

`main` is pushed up to `d006f6b`. Committed locally, NOT pushed:

- `67a415e` Breakfast list shared with Budget: Home card, list sheet, tick sync
  (new `Nudge/BreakfastSync.swift`, `Nudge/BreakfastView.swift`; small hooks in `ContentView.swift`;
  `LSApplicationQueriesSchemes = budget` in `Info.plist`; template placeholders; spec in
  `handoffs/HANDOFF_2026-11-19_breakfast-nudge-sync.md`)
- a few docs-only commits (this prompt + handoff)

This code has **never been compiled** (it was written in a sandbox without Xcode).

## Task

1. **Check Secrets without printing them:**
   ```bash
   git check-ignore -q ios/Nudge/Shared/Secrets.swift && echo "Secrets.swift ignored: OK"
   grep -c "budgetSupabaseURL\|budgetPublishableKey" ios/Nudge/Shared/Secrets.swift   # expect 2
   ```
2. **Read-only check that Budget's table exists** (prints only the HTTP code, row count and a
   week/status summary — never the key):
   ```bash
   python3 - <<'PY'
   import re, json, subprocess, collections
   s = open("ios/Nudge/Shared/Secrets.swift").read()
   url = re.search(r'budgetSupabaseURL = "([^"]+)"', s).group(1)
   key = re.search(r'budgetPublishableKey = "([^"]+)"', s).group(1)
   r = subprocess.run(["curl", "-s", "-m", "20", "-w", "\n%{http_code}", "-H", f"apikey: {key}",
        f"{url}/rest/v1/breakfast_list?select=week,status,changed_by"], capture_output=True, text=True)
   body, code = r.stdout.rsplit("\n", 1) if "\n" in r.stdout else ("", "000")
   print("HTTP", code)
   if code.startswith("2"):
       rows = json.loads(body); print(len(rows), "rows")
       print(collections.Counter((x["week"], x["status"]) for x in rows))
   else:
       print(body[:200].replace(key, "<key>"))
   PY
   ```
   - **HTTP 404** → the table isn't in Budget's project yet. **Stop** and tell Noah (Budget's
     migration `20261119000000_breakfast_list.sql` needs applying from the finance-tracker repo).
   - **HTTP 200 with 0 rows** → fine; Budget just hasn't been opened this week. Carry on, and tell
     Noah to open Budget once.
   - Anything else → stop and report.
3. Run `./reinstall_nudge.sh`. Report the **real** result for BOTH the iPhone and the Mac (check the
   actual install output; it has reported false success before).
4. **If the build fails:** you may fix **compile errors only**, and only in
   `BreakfastSync.swift`, `BreakfastView.swift` or the Breakfast lines in `ContentView.swift`.
   Minimal fixes, no behaviour changes. Commit them as
   `Breakfast: compile fixes` (never add `Secrets.swift`), rebuild, and show Noah the diff.
   Any other kind of failure → stop and report the exact error.
5. `git push` to `main`.
6. Tell Noah what to test:
   - Home shows a **Breakfast** card ("x of 15 bought · y left") under Pinned; tap it.
   - The sheet shows **This week · 16–22 Nov**, grouped by shop; **Next week** collapsed.
   - Tick "Single Lemon (1 of 7)" in Nudge → open Budget → that unit is ticked with today's day.
   - Tick a Yogurt unit in Budget → pull down in Nudge's Breakfast sheet → it's ticked.
   - Skip an item in Budget → it disappears from Nudge after a refresh.
   - Tap **Skip** in Nudge → message → **Open Budget** opens Budget on that week.
   - Same on the Mac.

## Finally — clean up locks

```bash
pgrep -x git >/dev/null || rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock .git/objects/maintenance.lock .git/stale-*
git status
git log origin/main --oneline -3
```
