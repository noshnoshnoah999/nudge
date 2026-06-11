# Nudge iOS — Xcode setup (first build)

This is the **foundation slice**: a native SwiftUI app that pulls your real synced reminders
from the shared Supabase backend and shows them in the 4 sections, with tap-to-complete.
Once this builds and runs, we'll add: add/edit, triage, EventKit (Apple Reminders sync), widgets.

## One-time project setup (~2 min in Xcode)

1. **Xcode → File → New → Project… → iOS → App → Next.**
2. Set:
   - **Product Name:** `Nudge`
   - **Organization Identifier:** `uk.flouty` (so the bundle id is `uk.flouty.nudge`)
   - **Interface:** SwiftUI · **Language:** Swift · Storage: None
3. Save it (anywhere, e.g. `~/Claude/Nudge-iOS-Project`).
4. Xcode generates `NudgeApp.swift` and `ContentView.swift`. **Delete both** (move to trash) —
   we're replacing them.
5. Drag these 4 files from `~/Claude/nudge-ios/` into the project's file list
   (check **"Copy items if needed"** and add to the **Nudge** target):
   - `NudgeApp.swift`
   - `Models.swift`
   - `NudgeStore.swift`
   - `ContentView.swift`
6. Set the deployment target to **iOS 16.0** or later
   (project → Targets → Nudge → General → Minimum Deployments).

## Build & run

- Pick an **iPhone 15 simulator** (or your own device) and press **▶︎ Run**.
- It needs internet (it reads your reminders from Supabase). You should see your real
  reminders grouped into **Overdue / Today / Upcoming / No Date**, with the overdue banner.
- Tap a circle to complete — it syncs back to the cloud (and your web app).

## If it doesn't build

Paste me the **exact error text** (and which file/line) and I'll fix it. First builds of
blind-written Swift usually need a tweak or two — that's expected.

## Notes
- No external packages needed (plain URLSession + Codable).
- The anon key is embedded (public-tier, same as the web app).
- Pull-to-refresh re-pulls from the cloud.
