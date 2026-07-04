// BackgroundTasks.swift — Nudge (iOS)
// Lets iOS wake Nudge overnight to run the end-of-day AI carry-over even when the app is
// closed. This is a best-effort, opportunistic wake (iOS picks the moment — usually when the
// device is idle and charging). The foreground catch-up in ContentView remains the guaranteed
// fallback: if iOS never grants a background run, the carry-over still fires next time Nudge
// is opened after 23:50.
//
// Not compiled into the Mac (Catalyst) build — BGTaskScheduler is iOS-only and Macs aren't
// asleep-with-app-closed the way phones are.

#if !targetEnvironment(macCatalyst)
import Foundation
import BackgroundTasks
import UIKit

enum CarryOverBGTask {
    static let identifier = "uk.flouty.Nudge.carryover"

    /// Register the launch handler. Must be called before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handle(task as! BGProcessingTask)
        }
    }

    /// Ask iOS to run us no earlier than the next 23:50. Safe to call repeatedly — it just
    /// replaces any pending request. iOS may run it later than requested, or not at all.
    static func schedule() {
        let req = BGProcessingTaskRequest(identifier: identifier)
        req.requiresNetworkConnectivity = true   // the carry-over calls the Claude API
        req.requiresExternalPower = false
        req.earliestBeginDate = next2350()
        do { try BGTaskScheduler.shared.submit(req) } catch {
            // Most commonly .unavailable on a free-signing/dev build or in the simulator — the
            // foreground catch-up covers us, so this is non-fatal.
        }
    }

    /// The next 23:50 local time strictly after now.
    private static func next2350(now: Date = Date()) -> Date {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: now)
        c.hour = 23; c.minute = 50
        let today = cal.date(from: c) ?? now
        return today > now ? today : (cal.date(byAdding: .day, value: 1, to: today) ?? today)
    }

    private static func handle(_ task: BGProcessingTask) {
        schedule()   // always queue the next night before doing any work

        let work = Task { @MainActor in
            let store = NudgeStore()
            await store.refresh()                 // pull the latest blob first
            await store.maybeRunDailyCarryOver()  // runs once/day, no-ops if already done
            await store.maybeRunDailyGrouping()   // overnight AI grouping, runs once/day
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}
#endif
