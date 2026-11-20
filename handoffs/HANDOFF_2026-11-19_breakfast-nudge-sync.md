# Breakfast shopping list ⇄ Nudge — spec and handoff (2026-11-19)

For: **Nudge's Claude** (and the Budget app's Claude, for the Budget half).
Owner: Noah. Written in the Budget project from the Budget code at commit 1557f2a.
**Status (2026-11-20): DONE on both sides.** Budget half built and pushed 2026-11-19
(main 72c6a20, table verified: 30 rows). Nudge half built, pushed, and confirmed working by
Noah on iPhone + Mac on 2026-11-20. See section 12 for the contract both apps now rely on.

> **Security first. Read before writing any code.**
> - This document deliberately contains **no keys, user keys or URLs with secrets**. Copy them
>   on Noah's Mac from the Budget code (`ios/Budget/Shared/Models.swift`:
>   `SUPABASE_PUBLISHABLE_KEY`; `ios/Budget/Budget/BudgetStore.swift`: `baseURL`).
>   **Never ask Noah to paste a key, token or password into chat.**
> - Nudge must **never** read or write the Budget app's `finance_data` table. It only talks
>   to the new `breakfast_list` table described in section 5.
> - Both GitHub repos (finance-tracker and nudge) are **public**. Budget's publishable key is
>   already in public code by design (public-tier key). Do not put any other secret in
>   either repo.
> - Supabase CLI work (creating the table): if the CLI isn't logged in, **stop and tell Noah**.
>   Do not change, print, set or ask for any secret.

---

## 1. What Noah wants (his words, summarised)

The Breakfast plan in the Budget app is a weekly shopping list. Noah wants it in Nudge too,
**synced both ways**:
- Ticking an item in Nudge ticks that exact item/unit in that week on Budget's Budget tab.
- Ticking it in Budget ticks it off in Nudge for that week.

### Decisions (Noah, 2026-11-19)
| Question | Answer |
|---|---|
| How the apps share ticks | **A small shared table** in Budget's Supabase project. Nudge never touches Budget's main data |
| Items bought more than once a week | **One line per unit**, e.g. "Single Lemon (3 of 7)". Each Nudge tick matches one unit in Budget |
| When the list shows in Nudge | **This week's list all week** (Mon–Sun), **plus Noah can look at next week** |
| Skip | Nudge **keeps a Skip button**, but it **doesn't skip**. Tapping it tells Noah to skip in Budget and offers to **open Budget at that week** (new `budget://` link, section 7) |
| Next week in Nudge | **Can be ticked** (shopping ahead) — confirmed |
| Items skipped in Budget | **Hidden** in Nudge — confirmed |
| New item added in Budget Settings mid-week | **Joins this week too** (and next week), in Budget and Nudge alike, unless that week is finished (ticked or skipped). Done by Budget; Nudge just sees new rows |

---

## 2. Noah's current Breakfast list (Budget → Settings → Breakfast plan, 2026-11-19)

| Item | Price | Per week | Where to buy | Week cost |
|---|---|---|---|---|
| Beef-Pork Mix Meat \| 450G | ¥625 | 2 | 肉匠かみむら 新浦安店 | ¥1,250 |
| ブルガリアヨーグルト カルシウムと鉄分 | ¥181 | 4 | ヤオコー | ¥724 |
| Batch of Bananas (5 Bananas) | ¥149 | 2 | 肉匠かみむら 新浦安店 | ¥298 |
| Single Lemon | ¥95 | 7 | 肉匠かみむら 新浦安店 | ¥665 |
| **Total** | | | | **¥2,937 a week** (¥11,748 per 4-week month) |

- Weeks currently **use ¥3,000 a week** (an amount change from Mon 16 Nov 2026). Budget shows a
  note that the list now comes to ¥2,937. Money is Budget's business. **Nudge shows no ¥
  totals except each line's price.**
- That's **15 units a week**: Meat 2 + Yogurt 4 + Bananas 2 + Lemon 7.
- Don't hard-code this list in Nudge. It changes in Budget Settings and reaches Nudge
  through the table.

---

## 3. How the Breakfast plan works in Budget (the rules Nudge must respect)

- **Weeks run Monday–Sunday.** A week is named by its Monday, `"YYYY-MM-DD"` (Japan time,
  device time zone). The plan started **Mon 16 Nov 2026**.
- **Weeks belong to pay periods** (payday to payday, like SUICA). A week belongs to the
  pay period its **Sunday** falls in. Nudge doesn't need this: Budget works out the week
  and puts it in each row (`week`, `pay_month`).
- **Each week keeps its own copy of the list** from the first tick, skip or edit in that
  week. Changing Settings later doesn't rewrite a started week.
- **Units.** An item with a weekly quantity above 1 splits into units "1 of N". A part
  quantity like 2.5 gives a last unit of size 0.5. Each unit ticks on its own and records
  the **day bought**. An item with quantity 1 or less has no units; the item itself is
  ticked.
- **Linked ticks** (all inside Budget):
  - Every unit ticked or skipped → the item is done.
  - Every item done or skipped → the **week is ticked** and its ¥ amount is **frozen**.
  - Unticking anything unticks the week.
  - Every item skipped → the week is skipped (¥0).
- **Skip** and **one-off price/quantity edits** change that week's money, so they happen
  in **Budget only**.

---

## 4. Budget's stored data (for reference — Nudge does NOT read this)

```jsonc
// settings.breakfast
{ "start": "2026-11-16",
  "items": [ { "id": "b1A2B3C4D5E6F", "name": "Single Lemon", "price": 95,
               "wqty": 7, "qty": 28, "shop": "肉匠かみむら 新浦安店" } ],
  "changes": [ { "id": "b…", "from": "2026-11-16", "weekly": 3000 } ] }

// data["2026-11"]  (budget/pay month)
{ "breakfastWeekItems": { "2026-11-16": [ /* that week's copy of items */ ] },
  "breakfastItemState": { "2026-11-16": {
      "b1A2B3C4D5E6F": { "done": true, "skip": true, "price": 90, "qty": 6,
                         "units": { "1": { "done": "2026-11-17" }, "2": { "skip": true } } } } },
  "breakfastPaid":    { "2026-11-16": 2937 },   // week ticked → frozen amount
  "breakfastSkipped": { "2026-11-23": true } }
```

### Key Budget code (Swift, `ios/Budget/Shared/Finance.swift`, struct `Calc`)

```swift
struct BreakfastUnit: Identifiable, Equatable {
    let index: Int; let of: Int; let size: Double   // size = 1, or the part left for the last unit
    let done: Bool; let doneOn: String?             // doneOn "" = done but no date known
    let skipped: Bool
    var handled: Bool { done || skipped }
}
struct BreakfastWeekItem: Identifiable, Equatable {
    let id: String; let name: String; let shop: String
    let price: Double; let qty: Double              // normal price and per-week quantity
    let oneOffPrice: Double?; let oneOffQty: Double?
    let markedDone: Bool; let skippedWhole: Bool
    let units: [BreakfastUnit]                      // empty when the week qty is 1 or less
    var skipped: Bool { skippedWhole || allUnitsSkipped }
    var done: Bool { units.isEmpty ? markedDone : (units.allSatisfy { $0.handled } && !allUnitsSkipped) }
    var weekPrice: Double { oneOffPrice ?? price }
    var weekQty: Double { oneOffQty ?? qty }
    // …
}
/// Units of an item bought `weekQty` times a week (none for 1 or less).
static func breakfastUnits(weekQty: Double, state: [String: JSONValue], itemDone: Bool) -> [BreakfastUnit] {
    guard weekQty > 1, weekQty.isFinite else { return [] }
    let n = min(99, Int(weekQty.rounded(.up)))
    return (1...n).map { i in
        let size = i < n ? 1 : ((weekQty - Double(n - 1)) * 100).rounded() / 100
        let u = state[String(i)]; let on = u?["done"]?.string
        return BreakfastUnit(index: i, of: n, size: size,
                             done: on != nil || (state.isEmpty && itemDone), doneOn: on,
                             skipped: u?["skip"]?.bool == true)
    }
}
func breakfastWeeks(_ mk: String) -> [String]                       // Mondays in pay month mk
func breakfastWeekItems(_ mk: String, _ mon: String) -> [BreakfastWeekItem]
func payMonth(containing ds: String) -> String                      // pay month for a day
```

### Budget's tick functions (`ios/Budget/Budget/BudgetStore.swift`). These are TOGGLES.

```swift
func toggleBreakfastItemDone(_ mk: String, _ mon: String, _ id: String)              // item with no units
func toggleBreakfastUnitDone(_ mk: String, _ mon: String, _ id: String, _ index: Int) // "n of N"; records today
func toggleBreakfastItemSkip(_ mk: String, _ mon: String, _ id: String)               // Budget UI only
func toggleBreakfastUnitSkip(_ mk: String, _ mon: String, _ id: String, _ index: Int) // Budget UI only
func toggleBreakfastPaid(_ mk: String, _ mon: String)     // whole week (ticks all items/units)
func setBreakfastMonthTicked(_ mk: String, _ on: Bool)    // main circle
```
They flip state. The sync code must **compare the wanted state with the current state and
only call a toggle when they differ.** A blind toggle would undo a tick.

---

## 5. The shared table — `breakfast_list` (in **Budget's** Supabase project)

One row per **unit** (or per item when it has no units), for **this week and next week**.

```sql
create table public.breakfast_list (
  id          text primary key,          -- "<week>|<item_id>|<unit>"  e.g. "2026-11-16|b1A2B3C4D5E6F|3"
  week        text not null,             -- Monday "YYYY-MM-DD"
  pay_month   text not null,             -- Budget month key "YYYY-MM" the week belongs to
  item_id     text not null,
  unit        int  not null default 0,   -- 0 = item has no units; else 1…unit_of
  unit_of     int  not null default 1,
  size        numeric not null default 1,-- 0.5 for a half last unit
  name        text not null,
  shop        text not null default '',
  price       numeric not null,          -- that week's price (one-off if set)
  sort        int  not null default 0,   -- Budget's list order
  status      text not null check (status in ('open','done','skipped')),
  done_on     text,                      -- "YYYY-MM-DD" day bought (Japan time), null if not done
  changed_by  text not null check (changed_by in ('budget','nudge')),
  updated_at  text not null              -- fixed-width UTC "2026-11-19T08:13:46.123Z" (string-compared)
);
create index breakfast_list_week on public.breakfast_list (week);
alter table public.breakfast_list enable row level security;
-- Same openness Noah knowingly chose for finance_data (publishable key, no login).
-- Holds only item names, shops, prices and ticks: nothing sensitive.
create policy breakfast_list_open on public.breakfast_list
  for all to anon using (true) with check (true);
```
- Add it as `supabase/migrations/2026xxxx_breakfast_list.sql` in finance-tracker. Claude Code
  applies it with the logged-in CLI. Not logged in → stop and tell Noah.
- `updated_at` uses the same fixed-width UTC stamp style as Nudge's `CloudSync.syncStamp()`,
  so comparing strings means comparing times.

### Who writes what
| Field | Budget writes | Nudge writes |
|---|---|---|
| Whole row (create / update / delete) | yes: it **owns** the list | **never creates or deletes rows** |
| `status` open ↔ done | yes | **yes, only open ↔ done** |
| `status` skipped | yes | **never** |
| `done_on` | yes | yes (today, when ticking; null when unticking) |
| `changed_by`, `updated_at` | `'budget'`, now | `'nudge'`, now |

Nudge updates with a PATCH on `id` that sends **only** `status, done_on, changed_by, updated_at`.
It must never touch name, price, shop, size or week.

---

## 6. Sync rules

### Budget side (to be built in the Budget app, iPhone + Mac together)
1. **Publish.** After any Breakfast change in Budget, and on each refresh (opening the
   app, then every 15 s while open), work out the rows for **this week and next week**
   from `breakfastWeekItems`:
   - unit rows for items with units;
   - one `unit 0` row for items without;
   - `status` = done / skipped / open.

   Upsert only the rows that differ from the table, stamped `changed_by 'budget'`. Delete
   that week's rows that no longer exist (item removed, quantity lowered).
2. **Apply Nudge's ticks** (before publishing).
   - Fetch both weeks' rows. Keep a small local map `rowId → last stamp Budget wrote or
     applied`.
   - For each row with `changed_by = 'nudge'` and `updated_at` newer than that stamp:
     if the row's status differs from Budget's current state, call
     `toggleBreakfastUnitDone` (unit ≥ 1) or `toggleBreakfastItemDone` (unit 0). Never
     call a toggle when the states already match.
   - Then record the stamp.
   - Use the row's `done_on` as the unit's bought day, not today. That means one small
     setter (or a parameter on the existing function) so that a tick made in Nudge on
     Tuesday still shows Tuesday when Budget opens on Thursday.
3. **Conflict rule:** newest `updated_at` wins per row. A Nudge tick on a row Budget has
   since **skipped** is ignored, and Budget republishes it as skipped.
4. **Week and month circles:** ticking the whole week, or the main circle, in Budget
   simply publishes every row as done. The linked week tick and frozen amount stay
   inside Budget, as today.
5. Errors: a failed upsert or fetch never blocks Budget's normal saving. Retry on the next
   refresh.

### Nudge side
1. Fetch `breakfast_list` where `week` = this Monday or next Monday (Japan time), ordered
   by `week, sort, unit`.
   - Refresh on open, on pull-to-refresh and on Nudge's normal sync timer.
   - Keep the last copy for offline viewing.
2. **Tick / untick** = PATCH that row (`done` + today, or `open` + null; `changed_by 'nudge'`,
   now).
   - Update the screen at once.
   - If offline, queue it and send it later. When it's sent, the newest stamp still wins.
3. Rows with `status = 'skipped'` are **hidden** (Noah's choice). Rows can appear,
   disappear or be renamed at any refresh — new items, removed items, quantity changes.
   Always redraw from the table; never keep Nudge-only copies of rows.
4. The Nudge widget may show this week's open count. That's optional; ask Noah.
5. Timing to tell Noah plainly:
   - A Nudge tick shows in Budget **the next time Budget is open** (within about 15 s of
     opening).
   - A Budget tick shows in Nudge on Nudge's next refresh.
   - Neither app can push to the other while it's closed. That would need server push,
     which is out of scope.

---

## 7. Skip button in Nudge + `budget://` link (new — both apps)

- Each Nudge row has a **Skip** button. Tapping it **never skips**. It shows:
  "Skips change your breakfast money, so do this in Budget." The buttons are
  **[Open Budget]** and **[OK]**.
- **[Open Budget]** opens `budget://breakfast?week=2026-11-16`.
- **Budget doesn't have a link scheme yet.** Budget's Claude adds one (both iPhone and Mac):
  - register the URL scheme `budget` in the app target's Info (CFBundleURLTypes);
  - add `.onOpenURL` in `BudgetApp.swift`. For `budget://breakfast?week=<Monday>` it opens
    the Budget tab on that week's pay month and expands the Breakfast plan row and that
    week.
  - Ignore anything it doesn't recognise, and treat the `week` value as untrusted: accept
    only a valid `YYYY-MM-DD` Monday, otherwise just open the Budget tab.
  - App Lock (Face ID) still applies before anything shows.
- If Budget isn't installed, or the link fails, Nudge just shows the message without the
  button.

---

## 8. Nudge screen (suggested — confirm look with Noah)

A "Breakfast" list in Nudge:

```
This week · 16–22 Nov                         6 of 15
  肉匠かみむら 新浦安店
    ○ Beef-Pork Mix Meat | 450G (1 of 2)  ¥625   Skip
    ● Beef-Pork Mix Meat | 450G (2 of 2)  ¥625   Tue 17
    ○ Single Lemon (1 of 7)               ¥95    Skip
    …
  ヤオコー
    ○ ブルガリアヨーグルト … (1 of 4)       ¥181   Skip
Next week · 23–29 Nov  ›   (collapsed)
```
- Rows are grouped by shop, which helps when shopping. A ticked row shows the day bought.
- A half unit shows "(3 of 3 · half)".
- No ¥ totals beyond each line's price. Budget owns the money.

---

## 9. Build order and checks

1. **Budget (Budget's Claude):**
   - the table migration;
   - publish + apply in BudgetStore, with `done_on` kept;
   - the `budget://` link.
   - Logic tests: row building from `breakfastWeekItems` (units, half unit, skipped);
     "apply only when different" (never a blind toggle); newest-wins.
   - Commit, then a Claude Code prompt to build, test, push and reinstall; it removes
     locks and stale locks at the end.
2. **Nudge (Nudge's Claude):** fetch and show both weeks; tick/untick PATCH with an offline
   queue; Skip message + Open Budget link; iPhone and Mac together.
3. **Two-device check (Noah):**
   - tick "Single Lemon (1 of 7)" in Nudge → open Budget → that unit is ticked with the
     same day;
   - tick a Yogurt unit in Budget → refresh Nudge → it's ticked;
   - skip an item in Budget → it leaves Nudge;
   - tap Skip in Nudge → Budget opens on that week;
   - tick everything for a week in Nudge → Budget's week circle is full and the week is
     ticked.

## 10. Out of scope / not decided
- Instant cross-app updates while an app is closed (server push): not planned.
- Adding or removing items from Nudge: not planned (Budget Settings only).

## 11. What the Budget half does (built 2026-11-19 — for Nudge's Claude to rely on)
- Table: `supabase/migrations/20261119000000_breakfast_list.sql` (exactly section 5).
- Budget fills rows for this week and next week whenever it refreshes (on open, then every
  15 s while open) and after every save. So rows exist only after Budget has been opened at
  least once in that week. Row ids: `"<Monday>|<item_id>|<unit>"`.
- `done_on` for an item with no units (unit 0) is whatever Nudge last wrote; Budget keeps it.
- Budget applies a Nudge row only when `changed_by = 'nudge'` and its `updated_at` is newer
  than what that Budget device last wrote/applied for the row. So **always send a fresh
  `updated_at` (fixed-width UTC, `.SSS` milliseconds, `Z`) with every PATCH**.
- Budget deletes rows of weeks before the current one once per launch.
- Link: `budget://breakfast?week=YYYY-MM-DD` (a Monday) opens the Budget tab on that week's
  pay month with the Breakfast plan and that week open. Anything else opens the Budget tab.
- Code: `ios/Budget/Budget/BreakfastListSync.swift`; logic + row building in
  `ios/Budget/Shared/Finance.swift` ("Breakfast ⇄ Nudge shared list"); tests
  `BreakfastNudgeSyncTests` (5).

## 12. Contract between Budget and Nudge (2026-11-20) — read before changing anything here
Both apps are live on this. **Do not change any of the following without telling Noah, so
he can tell Nudge's Claude first:**
- **Table `breakfast_list`**: its columns and their types (section 5).
- **Status values**: exactly `'open'`, `'done'`, `'skipped'`.
- **Row id format**: `"<Monday>|<item_id>|<unit>"` (unit 0 = item with no units).
- **Budget's Supabase URL or publishable key.** Nudge keeps its **own copy** in a
  gitignored `Secrets.swift`. If either ever changes (e.g. the key is rotated), tell Noah so
  Nudge gets updated, or Nudge's Breakfast list silently stops syncing.

What Nudge does (confirmed by Nudge's Claude, 2026-11-20):
- It only **PATCHes** `status` (open ↔ done), `done_on`, `changed_by = 'nudge'` and
  `updated_at`, guarded by `status=neq.skipped` and `updated_at=lt.<its stamp>`. Its stamp
  is always newer than the row's stamp it saw.
- It **never** creates, deletes or skips rows, and never reads `pay_month` or `finance_data`.
- It shows every week whose Sunday is today or later. In practice that's the two weeks
  Budget publishes (this week and next).
- There is **no Nudge widget** for Breakfast (Noah's choice).

What that means for Budget's side:
- Budget may freely add, update or delete rows. Nudge just redraws from the table.
- Budget must keep publishing `skipped` for skipped items/units (Nudge's guard relies on it),
  and keep stamps in the fixed-width UTC format (`.SSS` + `Z`). Nudge's `lt.` guard compares
  them as text.
- Budget code that carries this contract: `Calc.BreakfastListRow` and the
  "Breakfast ⇄ Nudge shared list" section in `ios/Budget/Shared/Finance.swift`, and
  `ios/Budget/Budget/BreakfastListSync.swift`.
