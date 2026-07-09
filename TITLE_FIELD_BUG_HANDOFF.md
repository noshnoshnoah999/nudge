# Handoff: Title field keyboard focus / double-tap-select bug (AddReminderView.swift)

**Status:** UNRESOLVED after two Cowork iterations. Second iteration introduced a regression.
Escalating to Opus in Claude Code because this needs on-device iteration in Xcode, not more
blind static-code edits.

**File:** `ios/Nudge/Nudge/AddReminderView.swift`, title `TextField` around lines 90-110.

---

## Timeline of what's been tried (read this fully before changing anything — do not repeat these)

### Original code (pre-session)
The title field was a vertical-axis `TextField` with a `simultaneousGesture(TapGesture().onEnded
{ titleFocused = true })` bolted on. A pre-existing code comment explained why:

> "a vertical-axis TextField inside a ScrollView won't become first responder on iOS (no keyboard
> on tap), though it works on Mac Catalyst. This focuses reliably."

So the gesture existed specifically to force the keyboard to open on tap, working around a known
SwiftUI limitation (multi-line/vertical-axis `TextField`s inside a `ScrollView` don't reliably
become first responder from a plain `.focused()` binding on iOS).

### Bug report #1 (user, iPhone only)
Double-tap-to-select a word did not work when **editing an existing reminder's** title or notes.
Worked fine on: new reminders (title auto-focuses 0.45s after view appears via `load()`, so the
user's tap lands on an already-focused field), and on Mac Catalyst (does not have the same
first-responder quirk).

**Hypothesis:** the `simultaneousGesture(TapGesture())` fires on *every* tap, including taps on an
already-focused field, and this was racing/interfering with the system's built-in double-tap
gesture recognizer for text selection.

### Iteration 1 (Cowork): gate the gesture
Changed both title and notes gestures to only fire if not already focused:
```swift
.simultaneousGesture(TapGesture().onEnded { if !titleFocused { titleFocused = true } })
.simultaneousGesture(TapGesture().onEnded { if !notesFocused { notesFocused = true } })
```
**Result when user retested:** partial fix. "Works on some reminders, not all" — specifically,
still failed when the title had wrapped to 2+ lines. Short/single-line titles worked; long/wrapped
titles didn't.

### Iteration 2 (Cowork): remove the gesture from the title field entirely
Since gating didn't fully fix it, removed the `simultaneousGesture` from the **title field only**
(left the notes field's gated version untouched, since the user only reported the multi-line
problem on the title). Title field now relies solely on `.focused($titleFocused)` with no
supplementary tap gesture.

**Result when user retested:** REGRESSION. The keyboard now does not open at all for longer
(multi-line/wrapped) reminders — only opens for single-line titles. This is exactly the original
pre-existing bug the removed gesture was there to prevent, now showing up specifically for the
multi-line case (previously it was presumably masked/inconsistent — the original comment just said
"won't become first responder," this session's testing suggests it's conditional on line count,
not universal).

### Current state of the code (as of this handoff)
```swift
TextField("What do you need to remember?", text: $title, axis: .vertical)
    .font(.system(.title3, design: .rounded).weight(.semibold))
    .foregroundStyle(Theme.textMain)
    .lineLimit(1...8)
    .focused($titleFocused)
    .padding(16)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
    // (no simultaneousGesture — removed in iteration 2)
```
Notes field (unchanged, still has the gated gesture from iteration 1):
```swift
TextField("Add notes…", text: $notes, axis: .vertical)
    .lineLimit(2...6).foregroundStyle(Theme.textMain).padding(.vertical, 10)
    .focused($notesFocused)
    .simultaneousGesture(TapGesture().onEnded { if !notesFocused { notesFocused = true } })
```
`load()` still auto-focuses the title 0.45s after view appears, but only for brand-new reminders
(`guard let r = editing else { ... titleFocused = true ... return }` — see lines ~446-454).

Neither `git commit` nor `git push` has happened yet for either iteration 1 or 2 — this is all
still sitting as an uncommitted working-tree change written by Cowork (which cannot commit; no
`.git` write access). **Do not assume any of this has shipped.** Check `git status` / `git diff`
first to see exactly what's uncommitted before doing anything.

`Changelog.swift` also has an uncommitted v2.30 entry describing the (incomplete) fix — this will
need rewriting once the real fix is found, not left describing an iteration that didn't work.

---

## The actual problem, stated plainly

Two behaviors are in tension and seemingly can't both be satisfied by tap-gesture tricks alone:

1. **Keyboard must open reliably on tap**, for both single-line and multi-line (wrapped) titles,
   for both new and existing reminders.
2. **Double-tap-to-select must work**, specifically when editing an *existing* reminder's title,
   and specifically on titles that wrap to 2+ lines.

Every gesture-based workaround tried so far fixes one and breaks (or partially breaks) the other,
because `simultaneousGesture(TapGesture())` intercepts tap events in a way that appears to
interfere with the system double-tap recognizer on multi-line text, but removing it entirely
breaks first-responder/focus behavior for multi-line `TextField(axis: .vertical)` in a
`ScrollView`.

## Suspected root cause

This smells like a known SwiftUI limitation, not a bug in this app's logic: `TextField(...,
axis: .vertical)` wrapped in a `ScrollView` has documented flakiness around becoming first
responder and around gesture/hit-testing once it grows past one line — likely because the
field's internal text container resizes and the tap coordinate space / first-responder chain
doesn't stay in sync with SwiftUI's gesture recognizers during/after that resize.

## Suggested directions to investigate (not prescriptive — use judgment once you can test on-device)

1. **Reproduce first, in Xcode with a real device/simulator**, both symptoms before changing code:
   - New reminder, type a long title that wraps to 2+ lines, tap away, tap back into the title —
     does the keyboard open? Does double-tap-select work?
   - Existing reminder with a long wrapped title — same two checks.
   - Existing reminder with a short single-line title — same two checks (control case that has
     supposedly worked throughout).
2. Consider whether the fix belongs on the **gesture** at all, or whether it's actually about
   `.focused($titleFocused)` + `axis: .vertical` interaction — e.g. does explicitly calling
   `titleFocused = true` in `.onTapGesture` (not `simultaneousGesture`) resolve differently? Native
   `.onTapGesture` claims the gesture rather than running in parallel — worth testing since it's a
   meaningfully different gesture-priority model from `simultaneousGesture`.
3. If gesture tricks can't satisfy both requirements, the more robust (but larger) fix is replacing
   the vertical-axis `TextField` with a `UIViewRepresentable`-wrapped `UITextView`, which has
   predictable native focus and text-selection behavior without fighting SwiftUI's gesture system.
   This is a real rewrite (auto-grow height, placeholder text, and focus-binding all need to be
   reimplemented) — don't reach for it first, but it's the fallback if gesture-based approaches keep
   trading one bug for another.
4. Whatever is tried, **test all four combinations** (new/existing × single-line/multi-line) before
   calling it fixed. The pattern in this session has been "fixes the reported case, breaks a case
   nobody explicitly tested."

## Safety / process notes for this project (per user's standing instructions)
- Confirm understanding with the user before making further changes if anything is ambiguous.
- Commit to git yourself once a fix is verified on-device, then either push directly (Claude Code
  has git access) or hand back a clear prompt if further Cowork work is needed.
- Remove any stale `.git/index.lock` (and `ios/Nudge/.git/index.lock`) at the end of the session so
  the next session starts clean.
- No API keys or secrets are involved in this bug — no special handling needed there.
