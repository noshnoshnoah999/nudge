# Handoff — 2026-11-19b: Breakfast list shared with Budget (Nudge half)

Spec: `handoffs/HANDOFF_2026-11-19_breakfast-nudge-sync.md` (written in the Budget project).
Claude Code prompt: `CLAUDE_CODE_PROMPT_2026-11-19b_breakfast-list.md`.

## Noah's decisions (this session)
- Entry point: a **Home card** that opens a Breakfast sheet (no 7th tab).
- **No widget** count for now.
- Budget's URL + publishable key live in the **gitignored `Shared/Secrets.swift`** (not committed),
  deviating from the spec's "public repo is fine".
- Earlier decisions in the spec stand: one line per unit, this week + next week (both tickable),
  skipped hidden, Skip = message + `budget://breakfast?week=` link.

## What was built — commit `67a415e` (NOT compiled yet, NOT pushed)
- `Nudge/BreakfastSync.swift` — `BreakfastStore.shared`:
  - GET `breakfast_list?week=gte.<today−6>`; shows the first two weeks whose Sunday ≥ today
    (Budget decides the weeks; Nudge never computes Mondays for fetching).
  - Tick/untick: PATCH `id=eq.X&status=neq.skipped&updated_at=lt.<stamp>` with only status,
    done_on, changed_by='nudge', updated_at. Stamp = `syncStamp(after: row.updated_at)` so it's
    strictly newer than the row seen (handles clock skew; Budget applies only newer stamps).
  - `Prefer: return=representation`; empty result = refused (skipped/newer) → dropped, next fetch
    redraws. Network/5xx → kept in a UserDefaults queue (`breakfast.pending.v1`).
  - Saved copy `breakfast.rows.v1` for offline. States: never / ok / offline / notSetUp (404).
  - Budget key in `apikey` header only; Nudge's Auth bearer is never sent to Budget's project.
- `Nudge/BreakfastView.swift` — `BreakfastHomeCard`, `BreakfastView` sheet (by shop, price per line,
  bought day "Tue 17", "(3 of 3 · half)"), `BudgetLink` (validates week as a real YYYY-MM-DD,
  `canOpenURL` needs the Info.plist query scheme).
- `ContentView` — `showBreakfast` state + sheet; card above the stat grid; `BreakfastStore.refresh()`
  fired (non-blocking) on launch, the 15 s poll and on foreground.
- `Info.plist` — `LSApplicationQueriesSchemes: [budget]`.

## Not verified
- The table's existence: this sandbox can't reach Supabase. Step 2 of the Claude Code prompt checks it.
- Compilation and on-device behaviour.

## Known limits / risks
- `breakfast_list` is open to anyone holding Budget's publishable key (Noah's accepted choice).
- A Nudge tick reaches Budget only when Budget is opened (no server push).
- Rare race on Budget's side: if Budget fetches, Nudge ticks, then Budget upserts within the same
  second, Budget's publish can overwrite the tick (Budget stamps newer). Low risk; Budget-side fix
  would be a conditional upsert.
