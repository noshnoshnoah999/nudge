# Claude Code prompt — 2026-08-28b — stop the Mac half reporting a false ✅

## Step 0 — clear the stale lock first

Cowork's `git status` left a lock it can't unlink (the mounted repo denies unlink on
`.git`). Before anything else:

```bash
cd ~/Claude/nudge
rm -f .git/index.lock
git status
```

## Context

Commit `d48bd92` fixed the iPhone install check (it was grepping devicectl's prose for
"installed", which also matches its failure text). Thank you — that one is done and
confirmed working on-device.

This is the same class of bug on the **Mac half**, which that commit didn't cover.

The Mac block notifies its own failures but does **not** `exit`, so control always fell
through to:

```bash
notify "Nudge" "✅ Reinstalled on iPhone + Mac — 7-day clock reset." "Glass"
```

A Mac failure therefore produced a failure notification immediately followed by a success
tick. The tick is the one that sticks in your head, which is exactly how the iPhone
problem went unnoticed for a week.

## What's uncommitted in `reinstall_nudge.sh`

- `MAC_OK=0` declared at the top of the Mac section
- `MAC_OK=1` set only on the real success path, right after
  `echo "Mac reinstalled to /Applications."`
- The final notify is now conditional: ✅ only when `MAC_OK=1`, otherwise
  "iPhone reinstalled — the Mac app did NOT update. See the failure above." with the
  Basso sound

Reaching that branch means the iPhone half succeeded, since it exits on failure — so the
message says exactly which half landed rather than claiming both.

Already verified with `bash -n`. Please read the diff before committing.

## Do NOT change these without asking Noah

- **The build destination.** Still `-destination 'generic/platform=iOS'`. Switching to
  `-destination "id=$DEV"` may be the permanent fix for the free-team `0xe8008012`
  profile problem, but it's unproven — Xcode's Cmd+R also registered the device, which may
  have been the whole cause. The script now fails loudly, so the next occurrence tells us
  for free. Changing it would also make the build require the device to be present.
- The `ls -td` DerivedData picker. Theoretically fragile (directory mtime doesn't track
  the binary inside), but there is only one `Nudge-*` folder on this Mac, so it is not
  currently a live bug. Leave it.

## Commit message

```
reinstall: don't report a Mac success when the Mac half failed

The Mac block notifies its failures but doesn't exit, so the final
"Reinstalled on iPhone + Mac" tick fired even after a failure notification.
Track MAC_OK and only claim both when both actually landed; otherwise say the
iPhone updated and the Mac didn't.

Same class as d48bd92 — a success message that survives a failure.
```

Push to `main`.

## Finally — clean up locks

After the commit and push both succeed:

```bash
rm -f .git/index.lock .git/HEAD.lock .git/refs/heads/main.lock
git status
```

Confirm `git status` is clean and the push landed.
