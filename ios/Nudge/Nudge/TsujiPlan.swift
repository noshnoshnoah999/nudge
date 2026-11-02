// TsujiPlan.swift — Nudge (iOS + Mac Catalyst)
// Tsuji Action Banner (spec "Nudge — Tsuji Action Banner", agreed with Noah 29 Oct 2026).
//
// ONLY the event UIDs are hardcoded here. Titles and dates always come live from the
// "Tsuji Plan" calendar in Apple Calendar, because many dates are estimates that will move.
//
// SAFETY — read before editing this file:
//  • Match on EKCalendarItem.calendarItemExternalIdentifier (the iCalendar UID). Never use
//    eventIdentifier or calendarItemIdentifier: they are local to one device and can change.
//  • Only these 13 events may ever be edited by Nudge. Never add any of the other 11 events in
//    Tsuji Plan (UIDs 01, 05, 06, 08, 09, 10, 11, 13, 18, 19, 20). UID 01 (16 Jan 2027 open
//    campus) has an invitee (Noah's mum): editing it would send her an update.
//  • The date suffix matters: UIDs 21–24 end in 20261029, the rest in 20261027.
//  • New action events from the Tsuji plan Claude use the same format:
//    tsuji-plan-NN-YYYYMMDD@noah.flouty.uk

import Foundation

enum TsujiPlan {
    /// The Apple Calendar (iCloud) calendar that holds the plan.
    static let calendarTitle = "Tsuji Plan"

    /// The 13 action events, in plan order (#1–#13). Generated from the spec's section 2 table.
    static let actionUIDs: [String] = [
        "tsuji-plan-24-20261029@noah.flouty.uk",   // #1  2027-01-09
        "tsuji-plan-02-20261027@noah.flouty.uk",   // #2  2027-01-31
        "tsuji-plan-03-20261027@noah.flouty.uk",   // #3  2027-03-15
        "tsuji-plan-04-20261027@noah.flouty.uk",   // #4  2027-04-30
        "tsuji-plan-21-20261029@noah.flouty.uk",   // #5  2027-08-15
        "tsuji-plan-07-20261027@noah.flouty.uk",   // #6  2027-09-01
        "tsuji-plan-12-20261027@noah.flouty.uk",   // #7  2027-12-01
        "tsuji-plan-22-20261029@noah.flouty.uk",   // #8  2028-03-15
        "tsuji-plan-14-20261027@noah.flouty.uk",   // #9  2028-08-01
        "tsuji-plan-23-20261029@noah.flouty.uk",   // #10  2028-08-15
        "tsuji-plan-15-20261027@noah.flouty.uk",   // #11  2028-09-01
        "tsuji-plan-16-20261027@noah.flouty.uk",   // #12  2028-10-15
        "tsuji-plan-17-20261027@noah.flouty.uk",   // #13  2028-11-01
    ]

    // MARK: - Master switch for editing Apple Calendar

    /// STEP 3 (2 Nov 2026): **true** — approved by Noah after every step 2 test passed and he
    /// backed up the Tsuji Plan calendar. Clearing an item now really edits that one Calendar
    /// event (COMPLETED prefix, a note line, alerts removed), and only after the typed phrase.
    /// Every write still goes through TsujiStore.saveToCalendar, which re-checks this switch and
    /// all guardrails on the event itself. Because this is true, the Test-mode entries (the
    /// made-up UID and UID 01) can no longer appear (TsujiStore.displayUIDs), and any dry-run
    /// clears from step 2 are forgotten, never written.
    /// To switch Calendar editing off again, set this back to false.
    static let calendarWritesEnabled = true

    // MARK: - Typed confirmation (spec section 6; approved choices 1 and 5)

    /// The phrase Noah types to clear an item. The clear sheet SHOWS it on screen — it is a
    /// confirmation, not a memory test (Noah, 29 Oct 2026).
    static let confirmPhrase = "Confirmed and completed"

    /// Case-sensitive; spaces/newlines at either end are ignored.
    static func phraseMatches(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines) == confirmPhrase
    }

    /// Prefix Nudge adds to a cleared event's title (en dash). Added only if the title doesn't
    /// already start with "COMPLETED".
    static let completedPrefix = "COMPLETED – "

    /// Cleared = the title starts with "COMPLETED", case-insensitive, after trimming spaces.
    static func isCompletedTitle(_ title: String) -> Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().hasPrefix("COMPLETED")
    }

    // MARK: - Guardrails (spec section 6, step 1 of "When he confirms")

    struct GuardInput {
        let uid: String
        let inTsujiPlanCalendar: Bool
        let hasAttendees: Bool
        let calendarEditable: Bool
        let repeats: Bool
    }

    /// Every reason an edit is refused; empty = allowed. A pure function so it can be tested
    /// with made-up values (Test mode → Safety self-test) without touching any real event.
    /// "repeats" is an extra rule on top of the spec: the spec never lets Nudge change
    /// recurrence, and editing one occurrence of a repeating event would split it.
    static func guardFailures(_ i: GuardInput) -> [String] {
        var f: [String] = []
        if !actionUIDs.contains(i.uid) { f.append("It isn't one of the 13 Tsuji action events.") }
        if !i.inTsujiPlanCalendar { f.append("It isn't in the Tsuji Plan calendar.") }
        if i.hasAttendees { f.append("It has invitees, so editing it would send them an update.") }
        if !i.calendarEditable { f.append("Its calendar is read-only.") }
        if i.repeats { f.append("It's a repeating event.") }
        return f
    }
}
