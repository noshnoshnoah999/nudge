# Claude Code prompt — widget tap-to-complete confirmation (2026-07-25e)

## ⚠️ READ THIS FIRST — HEAD currently does not build

`ec3353b` committed `ios/Nudge/Shared/WidgetBackgroundImageStore.swift` and a call to it from
`NudgeWidgets/TodayWidgetStyle.swift:142` (`WidgetBackgroundImageStore.loadImage()`), but the
**pbxproj registration for that file was never committed**. Verified: `WidgetBackgroundImageStore`
appears 0 times in `git show HEAD:ios/Nudge/Nudge.xcodeproj/project.pbxproj`. The file is
therefore not a member of any target and the `NudgeWidgets` target cannot compile at HEAD.

The fix is already in the working tree as an uncommitted `project.pbxproj` change. **It must be
committed.** Don't regenerate it — it's done and verified.

Please also confirm how `ec3353b` and `16d8f6f` were verified, because a widget build could not
have succeeded at those commits. If they were committed without a successful build, that's worth
correcting going forward — the whole point of these prompts is that the device is the arbiter.

## What this change adds

Noah asked for a confirmation before a widget tap completes a reminder. Background: during
testing it was briefly plausible that seven reminders had been silently completed by stray taps
while he poked the widget. They hadn't, but a single tap on a row writes a completion straight to
Supabase with no confirmation and no undo, so the risk is real.

**A system confirmation dialog is not possible.** `AppIntent.requestConfirmation()` is ignored
when the intent runs from a widget `Button(intent:)` — a known WidgetKit limitation, widgets can't
present UI (Apple Developer Forums 732037, 732904). So confirmation is built from a second tap.

**Behaviour — tap once to arm, tap the same row again to confirm:**
- 1st tap → stores `{id, armedAt}`, reloads the timeline. That row renders **struck through with
  "tap again"** at `.primary` brightness. **Nothing is written to Supabase.**
- 2nd tap on the same row, within **10 seconds** (Noah's chosen window) → completes for real.
- Tap a different row while one is armed → the new row arms; the first is forgotten.
- No second tap → a scheduled timeline entry at `armedAt + 10s` clears the armed look.
- Fails safe: expired arm, different row armed, or no stored state all fall through to *arming*,
  never to completing. A stray tap can never complete anything on its own.

## Files

**New — pbxproj registration ALREADY DONE, do not redo:**
- `ios/Nudge/Shared/WidgetPendingCompletionStore.swift` → registered in **both** targets
  (fileRef `608FA682CC6A99D24FEAE55B`, build files `AF584F76E8C3AC5E3B593FD1` /
  `FCCE7C30E68BDCC859B1B189`), mirroring `AuthStore.swift`. Verified: no duplicate object IDs,
  exactly one entry in each Sources phase (app `3A9BD1EC…`, widget `6E30D814…`).

**Modified:**
- `Shared/CompleteReminderWidgetIntent.swift` — `perform()` now arms on first tap, completes on
  confirmed second tap.
- `NudgeWidgets/NudgeWidgets.swift` — `TodayConfigEntry` gains `pendingId` and an explicit `date`;
  `TodayConfigProvider.timeline` emits the disarm entry; `TodayWidgetView` takes `pendingId`;
  `WidgetRowTitle` gains `armed`.
- `Nudge.xcodeproj/project.pbxproj` — registrations for **both** new shared files.

## Why the Keychain for the armed state

iOS doesn't firmly guarantee which process performs a widget intent — there are reports of it
being routed to the containing app while the app is running (Forums 732771). `UserDefaults.standard`
would then be a different store than the timeline provider reads and the handshake would break.
The shared Keychain access group is readable from both, needs no App Group (free team), and is
already used for the session. It's UI state, not a secret — the Keychain is for reachability.

## Design constraint worth preserving

`WidgetRowTitle` builds the armed row as a **single concatenated `Text`**, not an `HStack`, so the
row's height does not change when it arms. If the height changed, `rowLimit(for:)` would disagree
with reality and the list could overflow the widget again — the exact bug fixed in `16d8f6f`.
Don't refactor that into a stack.

## What to do

1. `git diff` and review, including `project.pbxproj`.
2. Build the widget extension and the app. **This is the first build that can succeed since
   `ec3353b`** — expect the missing-symbol error to be gone now that registration is committed.
3. Test on device:
   - Tap a row once → it goes struck-through with "tap again". **Verify in the app that the
     reminder is still open** — nothing should have been written.
   - Tap it again within 10s → it completes and drops off. Confirm in the app.
   - Tap once, wait >10s, tap again → the second tap should re-arm, NOT complete. Verify the
     reminder is still open, then confirm on a third tap.
   - Tap row A, then row B → B is armed, A is back to normal. Tap B again → only B completes.
   - Leave a row armed and don't tap → within ~10s it returns to normal by itself.
   - Check the armed row is legible in Apple **tinted** mode with the near-black background —
     it uses `.primary` and strikethrough, but confirm the "tap again" hint is readable at both
     the smallest (12) and largest (40) font sizes.
   - Confirm rows still don't overflow at any font size, and the background is still true black
     (`#000000` card vs `#000000` wallpaper). Don't regress `023dbb7` or `16d8f6f`.
4. Commit — separate the build fix from the feature:
   - `fix(xcode): register WidgetBackgroundImageStore in app + widget targets`
   - `feat(widget): require a confirming second tap before completing from the widget`
5. Push to `origin/main`.
6. **After committing and pushing, remove any locks or stale locks** (`.git/index.lock`, leftover
   Xcode DerivedData locks) so the next session starts clean.

## Safety notes

- No secrets; don't add any. Don't add `kSecAttrSynchronizable` to either Keychain item — both
  are deliberately device-local.
- No data model or auth changes. The only Supabase write is the existing completion, now gated
  behind the second tap.

## Report back

Confirm: (a) the widget target builds, (b) a single tap provably does NOT complete a reminder,
and (c) the 10-second expiry re-arms rather than completes.
