# Claude Code prompt — 2026-08-28 — commit the reinstall-script install-check fix

## Step 0 — clear any stale lock first

```bash
cd ~/Claude/nudge
rm -f .git/index.lock
git status
```

## Context — do not "fix" this differently, the cause is confirmed

`reinstall_nudge.sh` reported success on every run while the iPhone install was actually
failing. The iPhone ran a build from ~20 Aug for about a week; the Mac was fine, which is
what made it look like a platform-specific code bug. It was not — the source compiles for
iOS and always did (`BUILD SUCCEEDED` for `generic/platform=iOS`).

The real install error, captured by running `devicectl` by hand:

```
0xe8008012 (This provisioning profile cannot be installed on this device.)
ApplicationVerificationFailed
Failed to install embedded profile for uk.flouty.Nudge
```

And the reason nobody saw it — the old success check was:

```bash
if echo "$OUT" | grep -qiE "installed|databaseUUID"; then
```

devicectl's failure text is *"This app cannot be **installed** because its integrity could
not be verified"*. That matches. So a failed install was read as a success: the script
launched the OLD app, printed "iPhone reinstalled", built the Mac, and ended with
"✅ Reinstalled on iPhone + Mac".

This is the third instance of the same class of bug in this script — its own comments
already record two others (`pipefail` masking a build failure, and launching from
DerivedData while `/Applications` stayed stale).

**Resolved on-device**: Noah opened the project in Xcode, selected his iPhone as the
destination, and pressed Cmd+R. That registered the device and re-minted a working
profile. The buy chips now show on the iPhone.

## What's uncommitted

`reinstall_nudge.sh` — the install check now:

- judges by **exit code**, not by grepping prose
- also fails on any `^ERROR:` line, in case devicectl ever exits 0 on a partial failure
- prints the last 25 lines of real output on failure
- names the cause: `0xe8008012` / `ApplicationVerificationFailed` → tells the user to open
  Xcode and press Run to repair signing, instead of the old and actively misleading
  "unlock & reconnect your iPhone"

Already verified with `bash -n`. Please read the diff before committing.

Also untracked, please add them:

- `CLAUDE_CODE_PROMPT_2026-08-20_completed-today-section.md`
- `CLAUDE_CODE_PROMPT_2026-08-21_nextup-prefer-upcoming.md`
- `CLAUDE_CODE_PROMPT_2026-08-27_buy-date-chips.md`
- `CLAUDE_CODE_PROMPT_2026-08-28_reinstall-false-success.md` (this file)

## Do NOT change these without asking Noah

- **The build destination.** The script still builds with `-destination 'generic/platform=iOS'`.
  Switching to `-destination "id=$DEV"` may be the permanent fix for the free-team profile
  problem, but it is unproven — Xcode's Run also registered the device, which may have been
  the whole cause. The script now fails loudly, so the next run will tell us for free.
  Changing it also makes the build require the device to be present. Leave it.
- The Mac half. Its `pipefail` and `/Applications` staging are correct as they stand.

## Commit message

```
reinstall: judge the iPhone install by exit code, not by grepping its output

The success check was `grep -qiE "installed|databaseUUID"`, which also matches
devicectl's failure text — "This app cannot be installed" contains "installed".
A signing failure therefore read as success: the script launched the old app,
reported "iPhone reinstalled" and carried on to the Mac. The iPhone silently ran
a week-old build while every run finished with a tick.

Now checks the exit code, treats any ERROR: line as failure, prints the real
output, and names the cause — a 0xe8008012 points at Xcode signing rather than
telling the user to reconnect a phone that was never the problem.
```

Push to `main`.

## Finally — clean up locks

After the commit and push both succeed:

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock
git status
```

Confirm `git status` is clean and the push landed.
