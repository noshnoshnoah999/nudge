// NudgeIntents.swift — Nudge (iOS)
// App Intents that expose Nudge to Siri, the Shortcuts app, and Automations. Each runs in
// the background (no app launch needed) against a fresh NudgeStore that pulls the latest
// cloud state, mutates, and flushes immediately — the same pattern the notification handler
// uses. The running app picks up changes on its next refresh.

import AppIntents
import Foundation

// MARK: - Add a reminder

struct AddReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Reminder"
    static var description = IntentDescription("Add a new reminder to Nudge, optionally with a date and time.")

    @Parameter(title: "Reminder") var text: String
    @Parameter(title: "Date & time") var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text) to Nudge on \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = NudgeStore()
        await store.refresh()
        let hasDue = date != nil
        store.saveReminder(editing: nil, title: text, notes: "",
                           hasDue: hasDue, due: date ?? Date(), hasTime: hasDue,
                           listId: "reminders", priority: "normal")
        await store.persistNow()
        return .result(dialog: "Added “\(text)” to Nudge.")
    }
}

// MARK: - What's due today

struct WhatsDueTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "What's Due Today"
    static var description = IntentDescription("Get today's reminders and how many are overdue.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let store = NudgeStore()
        await store.refresh()
        let today = store.todayReminders()
        let overdue = store.pastDayOverdueCount()
        if today.isEmpty && overdue == 0 {
            return .result(value: "Nothing due today.", dialog: "Nothing due today — you're all clear.")
        }
        var headline = "\(today.count) due today"
        if overdue > 0 { headline += " · \(overdue) overdue" }
        let list = today.prefix(12).map { "• \(displayTitle($0))" }.joined(separator: "\n")
        let value = list.isEmpty ? headline : "\(headline)\n\(list)"
        return .result(value: value, dialog: "\(headline).")
    }
}

// MARK: - Complete / Snooze a reminder by name

struct CompleteReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Reminder"
    static var description = IntentDescription("Mark a Nudge reminder complete by name.")

    @Parameter(title: "Reminder name") var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = NudgeStore()
        await store.refresh()
        guard let match = bestMatch(name, in: store.open()) else {
            return .result(dialog: "Couldn't find an open reminder matching “\(name)”.")
        }
        store.toggleComplete(match)
        await store.persistNow()
        return .result(dialog: "Completed “\(displayTitle(match))”.")
    }
}

struct SnoozeReminderIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze Reminder"
    static var description = IntentDescription("Push a Nudge reminder out by one hour.")

    @Parameter(title: "Reminder name") var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = NudgeStore()
        await store.refresh()
        guard let match = bestMatch(name, in: store.open()) else {
            return .result(dialog: "Couldn't find an open reminder matching “\(name)”.")
        }
        store.snooze(match, minutes: 60)
        await store.persistNow()
        return .result(dialog: "Snoozed “\(displayTitle(match))” for an hour.")
    }
}

/// Loose title match for the "by name" intents: exact-ish first, then contains either way.
@MainActor
private func bestMatch(_ query: String, in reminders: [Reminder]) -> Reminder? {
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    guard !q.isEmpty else { return nil }
    if let exact = reminders.first(where: { displayTitle($0).lowercased() == q }) { return exact }
    return reminders.first { r in
        let t = displayTitle(r).lowercased()
        return t.contains(q) || q.contains(t)
    }
}

// MARK: - Siri phrases / Shortcuts gallery

struct NudgeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddReminderIntent(),
                    phrases: ["Add a reminder to \(.applicationName)",
                              "Add a \(.applicationName) reminder",
                              "New \(.applicationName) reminder",
                              "Add to \(.applicationName)"],
                    shortTitle: "Add Reminder", systemImageName: "plus.circle.fill")
        // "What's due" collides with Siri's built-in Calendar/Reminders domain and can lose
        // to it even on an exact-text match (confirmed by Noah 2026-07-24: typing "What's due
        // in Nudge" opened Calendar, not this intent). "Nudge status" is app-name-first and
        // avoids that phrase pattern; kept as the lead phrase with the old ones as aliases.
        AppShortcut(intent: WhatsDueTodayIntent(),
                    phrases: ["\(.applicationName) status",
                              "What's due in \(.applicationName)",
                              "What's due today in \(.applicationName)"],
                    shortTitle: "What's Due Today", systemImageName: "checklist")
        AppShortcut(intent: CompleteReminderIntent(),
                    phrases: ["Complete a reminder in \(.applicationName)",
                              "Mark a \(.applicationName) reminder done"],
                    shortTitle: "Complete Reminder", systemImageName: "checkmark.circle.fill")
        AppShortcut(intent: QuickAddReminderIntent(),
                    phrases: ["Quick add to \(.applicationName)"],
                    shortTitle: "Quick Add", systemImageName: "bell.badge.fill")
        // Previously unreachable by Siri — defined in this file but never registered.
        AppShortcut(intent: SnoozeReminderIntent(),
                    phrases: ["Snooze a \(.applicationName) reminder"],
                    shortTitle: "Snooze Reminder", systemImageName: "zzz")
        // Previously only reachable via the Control Center button — now also a Siri phrase.
        AppShortcut(intent: QuickCatchIntent(),
                    phrases: ["\(.applicationName) it"],
                    shortTitle: "Catch a Thought", systemImageName: "bubble.left.and.text.bubble.right.fill")
    }
}
