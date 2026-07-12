# Claude Code prompt — AI grouping fix (2026-07-12)

Paste this into Claude Code in the `nudge` repo.

---

I edited `ios/Nudge/Nudge/AIGrouper.swift` in Cowork (prompt-only change, no schema/model
changes). Context: the AI grouping feature grouped "Cancel YouTube Premium Lite trial via
LINEMO" with "Calculate SUICA charge amount" under a title "Tokyo Transport & Services" —
these are unrelated tasks that only shared a loose "Japan / a service" association, not a
real link. The system prompt was too permissive (matched on topic/location tags instead of
requiring a concrete shared action).

I tightened the system prompt in `AIGrouper.swift` to:
- Require groups share a genuine concrete link (same project/trip/errand/repeated task), not
  just a surface tag (country, company, app, category).
- Add the LINEMO/SUICA case as an explicit "bad example, do NOT do this" in the prompt.
- Require the group title be literally true for every member, not just vague-but-plausible.
- Add "when in doubt, leave it out" to the existing conservative principles.

Please:
1. `git diff ios/Nudge/Nudge/AIGrouper.swift` and review the change for sanity (it's prompt
   text only — no Swift logic/schema changed, so it should compile as-is, but confirm no
   syntax issues in the string literal).
2. Build the iOS/macOS Catalyst target to confirm it still compiles.
3. Commit with message: `fix: tighten AI grouping prompt to require concrete task link, not just topic overlap`
4. Push to origin/main.
5. At the end, remove any locks or stale locks (e.g. `.git/index.lock` or similar) so the
   next Cowork/Claude Code session starts clean.

Note: this is a prompt-quality fix, not a guaranteed elimination of bad groupings — Claude
(Sonnet) is still doing subjective clustering, so spot-check the next few nightly grouping
runs to confirm the fix actually holds in practice before considering this closed.
