// TsujiIDCheckView.swift — Nudge (iOS + Mac Catalyst)
// Tsuji Action Banner, step 1 — "Test 0" (spec section 10).
//
// A READ-ONLY check that Nudge can find the 13 Tsuji action events in the "Tsuji Plan"
// calendar by their iCalendar UID (EKCalendarItem.calendarItemExternalIdentifier).
//
// SAFETY: this screen never saves, edits or deletes anything. It has its own EKEventStore
// and calls only read APIs: authorizationStatus, calendars(for:), predicateForEvents and
// events(matching:). There is no call to save/remove anywhere in this file — keep it that way.
// Attendee names/emails are never read or shown; only the yes/no hasAttendees flag.
//
// How it's used: Settings → Tsuji plan → Calendar ID check. Noah taps "Copy report" and
// pastes the text to Claude, who decides PASS/FAIL against the spec. If it fails, the build
// stops there (spec: "do not invent another matching method").

import SwiftUI
import UIKit
import EventKit

/// Test 0 expectations — each action event's start date and title on 29 Oct 2026, from the
/// spec's section 2 table (generated from the spec, not retyped). Used ONLY by this check:
/// the real feature reads titles and dates live from Calendar, because they will change.
private let test0Expected: [String: (start: String, title: String)] = [
    "tsuji-plan-24-20261029@noah.flouty.uk": (start: "2027-01-09", title: "Check open campus entry pass (参加証) has arrived"),   // #1
    "tsuji-plan-02-20261027@noah.flouty.uk": (start: "2027-01-31", title: "Japanese study checkpoint 1 – timed practice test"),   // #2
    "tsuji-plan-03-20261027@noah.flouty.uk": (start: "2027-03-15", title: "Check JLPT July registration has opened (estimate)"),   // #3
    "tsuji-plan-04-20261027@noah.flouty.uk": (start: "2027-04-30", title: "Japanese study checkpoint 2 – timed practice test"),   // #4
    "tsuji-plan-21-20261029@noah.flouty.uk": (start: "2027-08-15", title: "Register for December JLPT – opens mid/late Aug (estimate)"),   // #5
    "tsuji-plan-07-20261027@noah.flouty.uk": (start: "2027-09-01", title: "Start kitchen job search"),   // #6
    "tsuji-plan-12-20261027@noah.flouty.uk": (start: "2027-12-01", title: "Check if Tsuji 2029 入学要項 is published (estimate)"),   // #7
    "tsuji-plan-22-20261029@noah.flouty.uk": (start: "2028-03-15", title: "Register for July JLPT – opens mid/late Mar (estimate)"),   // #8
    "tsuji-plan-14-20261027@noah.flouty.uk": (start: "2028-08-01", title: "Ask TIHS for graduation certificate"),   // #9
    "tsuji-plan-23-20261029@noah.flouty.uk": (start: "2028-08-15", title: "Register for December JLPT – opens mid/late Aug (estimate)"),   // #10
    "tsuji-plan-15-20261027@noah.flouty.uk": (start: "2028-09-01", title: "Tsuji eligibility screening applications open (estimate)"),   // #11
    "tsuji-plan-16-20261027@noah.flouty.uk": (start: "2028-10-15", title: "Create Tsuji online application account + take ID photo"),   // #12
    "tsuji-plan-17-20261027@noah.flouty.uk": (start: "2028-11-01", title: "Tsuji general exam – round 1 window (estimate)"),   // #13
]

@MainActor
final class TsujiIDCheck: ObservableObject {
    @Published private(set) var report = ""
    @Published private(set) var verdict = ""
    @Published private(set) var passed: Bool?
    @Published private(set) var needsAccess = false
    @Published private(set) var hasRun = false

    private var store = EKEventStore()

    private struct Row {
        let externalID: String?
        let title: String
        let start: String
        let end: String
        let startDate: Date
        let isAllDay: Bool
        let hasAttendees: Bool
        let hasRecurrence: Bool
        let alarms: [String]
        let calendarTitle: String
    }

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    /// Asks for Full Access through Nudge's existing CalendarService (iOS only shows the
    /// prompt if it has never been asked), then re-runs the check.
    func requestAccess() async {
        await CalendarService.shared.requestAccessIfNeeded()
        store = EKEventStore()   // a store created before access was granted may see no calendars
        run()
    }

    func run() {
        hasRun = true
        needsAccess = false
        var out: [String] = []
        var failures: [String] = []
        var warnings: [String] = []

        let device = ProcessInfo.processInfo.isMacCatalystApp ? "Mac" : UIDevice.current.model
        out.append("NUDGE TSUJI TEST 0 — read-only calendar ID check")
        out.append("Run: \(stampFormatter.string(from: Date())) (\(TimeZone.current.identifier)) on \(device)")

        // 1. Access
        let status = EKEventStore.authorizationStatus(for: .event)
        out.append("Calendar access: \(Self.name(of: status))")
        guard status == .fullAccess else {
            needsAccess = (status == .notDetermined)
            failures.append("Nudge does not have Full Access to Calendar, so it can't read events.")
            finish(out: &out, failures: failures, warnings: warnings)
            return
        }

        // 2. The Tsuji Plan calendar
        let allCals = store.calendars(for: .event)
        let tsujiCals = allCals.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines) == TsujiPlan.calendarTitle
        }
        out.append("")
        out.append("Calendars named \"\(TsujiPlan.calendarTitle)\": \(tsujiCals.count)")
        for c in tsujiCals {
            out.append("  - account: \(c.source?.title ?? "?") | type: \(Self.name(of: c.type)) | editable: \(c.allowsContentModifications ? "yes" : "NO") | id: \(c.calendarIdentifier)")
        }
        if tsujiCals.isEmpty {
            failures.append("No calendar named \"\(TsujiPlan.calendarTitle)\" was found on this device.")
            finish(out: &out, failures: failures, warnings: warnings)
            return
        }
        if tsujiCals.count > 1 {
            failures.append("More than one calendar is named \"\(TsujiPlan.calendarTitle)\" — Nudge can't tell which is the real one.")
        }
        if tsujiCals.contains(where: { !$0.allowsContentModifications }) {
            warnings.append("A Tsuji Plan calendar is read-only, so clearing items could not update Calendar.")
        }

        // 3. Search window: today − 1 year, for 4 years minus a day (EventKit caps a search at
        //    four years; staying one day under means it is never silently shortened).
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .year, value: -1, to: today) ?? today
        let fourYears = cal.date(byAdding: .year, value: 4, to: start) ?? today
        let end = cal.date(byAdding: .day, value: -1, to: fourYears) ?? today
        out.append("Search window: \(dayFormatter.string(from: start)) to \(dayFormatter.string(from: end))")

        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: tsujiCals))
        let rows = events.map { self.makeRow($0) }.sorted { $0.startDate < $1.startDate }
        out.append("Events found in Tsuji Plan: \(rows.count) (spec: 24)")

        // 4. The 13 action events
        out.append("")
        out.append("THE 13 ACTION EVENTS")
        var actionFound = 0
        for (index, uid) in TsujiPlan.actionUIDs.enumerated() {
            let n = index + 1
            let matches = rows.filter { $0.externalID == uid }
            let expected = test0Expected[uid]
            out.append("#\(n) \(uid)")
            if matches.isEmpty {
                out.append("   NOT FOUND")
                failures.append("#\(n) not found.")
                continue
            }
            if matches.count > 1 {
                out.append("   FOUND \(matches.count) TIMES")
                failures.append("#\(n) found \(matches.count) times (must be exactly once).")
            }
            actionFound += 1
            for r in matches {
                let dateOK = (r.start == expected?.start)
                let titleOK = (r.title.trimmingCharacters(in: .whitespacesAndNewlines) == expected?.title)
                out.append("   start \(r.start)\(r.end != r.start ? " → end \(r.end)" : "") \(dateOK ? "OK" : "DIFFERENT (spec \(expected?.start ?? "?"))")")
                out.append("   title \"\(r.title)\" \(titleOK ? "OK" : "DIFFERENT")")
                if !titleOK { out.append("         spec: \"\(expected?.title ?? "?")\"") }
                out.append("   all-day: \(r.isAllDay ? "yes" : "NO") | invitees: \(r.hasAttendees ? "YES" : "no") | repeats: \(r.hasRecurrence ? "YES" : "no")")
                out.append("   alarms: \(r.alarms.isEmpty ? "none on the event" : r.alarms.joined(separator: "; "))")
                if !dateOK { failures.append("#\(n) start date is \(r.start), spec says \(expected?.start ?? "?").") }
                if !titleOK { failures.append("#\(n) title differs from the spec.") }
                if !r.isAllDay { warnings.append("#\(n) is not an all-day event.") }
                if r.hasAttendees { warnings.append("#\(n) has invitees — Nudge would refuse to edit it.") }
                if r.hasRecurrence { warnings.append("#\(n) repeats — the spec assumes no action event repeats.") }
            }
        }
        out.append("Action events found: \(actionFound) of \(TsujiPlan.actionUIDs.count)")

        // 5. Everything else in Tsuji Plan (must be ignored by the feature)
        let others = rows.filter { r in !TsujiPlan.actionUIDs.contains(where: { $0 == r.externalID }) }
        out.append("")
        out.append("OTHER EVENTS IN TSUJI PLAN (ignored): \(others.count) (spec: 11)")
        for r in others {
            out.append("  - \(r.start) | \(r.externalID ?? "(no ID)") | invitees: \(r.hasAttendees ? "YES" : "no") | \"\(r.title)\"")
        }
        if others.count != 11 { warnings.append("Found \(others.count) non-action events, spec says 11.") }
        if others.contains(where: { $0.externalID == nil }) || rows.contains(where: { $0.externalID == nil }) {
            warnings.append("Some events have no external ID.")
        }

        // 6. Safety check for the guardrail: UID 01 (open campus, Noah's mum invited) must
        //    report invitees, otherwise the "has attendees" guardrail could not protect it.
        out.append("")
        let uid01 = rows.filter { $0.externalID?.hasPrefix("tsuji-plan-01-") == true }
        if uid01.isEmpty {
            out.append("SAFETY CHECK — UID 01 (open campus with invitee): NOT FOUND")
            warnings.append("UID 01 not found, so the invitee guardrail could not be checked.")
        } else {
            let ok = uid01.allSatisfy { $0.hasAttendees }
            out.append("SAFETY CHECK — UID 01 (open campus with invitee): invitees reported = \(ok ? "YES (guardrail works)" : "NO")")
            if !ok { warnings.append("UID 01 does not report invitees — the invitee guardrail would NOT protect it.") }
        }

        // 7. Copies of the 13 UIDs in OTHER calendars (e.g. the ICS imported twice).
        let tsujiIDs = Set(tsujiCals.map { $0.calendarIdentifier })
        let otherCals = allCals.filter { !tsujiIDs.contains($0.calendarIdentifier) }
        var elsewhere: [String] = []
        if !otherCals.isEmpty {
            let pred = store.predicateForEvents(withStart: start, end: end, calendars: otherCals)
            for e in store.events(matching: pred) {
                let ext: String? = e.calendarItemExternalIdentifier
                if let ext, TsujiPlan.actionUIDs.contains(ext) {
                    elsewhere.append("  - \(ext) in \"\(e.calendar?.title ?? "?")\"")
                }
            }
        }
        out.append("Copies of the 13 in other calendars: \(elsewhere.isEmpty ? "none" : "\(elsewhere.count)")")
        out.append(contentsOf: elsewhere)
        if !elsewhere.isEmpty { warnings.append("Some action UIDs also exist in other calendars (Nudge only looks in Tsuji Plan).") }

        finish(out: &out, failures: failures, warnings: warnings)
    }

    private func finish(out: inout [String], failures: [String], warnings: [String]) {
        passed = failures.isEmpty
        verdict = failures.isEmpty
            ? (warnings.isEmpty ? "PASS" : "PASS, with \(warnings.count) warning\(warnings.count == 1 ? "" : "s")")
            : "FAIL — \(failures.count) problem\(failures.count == 1 ? "" : "s")"
        var head = ["RESULT: \(verdict)"]
        if !failures.isEmpty { head.append("Problems:"); head += failures.map { "  - \($0)" } }
        if !warnings.isEmpty { head.append("Warnings:"); head += warnings.map { "  - \($0)" } }
        head.append("")
        report = (head + out).joined(separator: "\n")
    }

    private func makeRow(_ e: EKEvent) -> Row {
        let startDate: Date = e.startDate ?? .distantPast
        let endDate: Date = e.endDate ?? startDate
        let ext: String? = e.calendarItemExternalIdentifier
        return Row(
            externalID: ext,
            title: e.title ?? "",
            start: dayFormatter.string(from: startDate),
            end: dayFormatter.string(from: endDate),
            startDate: startDate,
            isAllDay: e.isAllDay,
            hasAttendees: e.hasAttendees,
            hasRecurrence: e.hasRecurrenceRules,
            alarms: (e.alarms ?? []).map { self.describe($0) },
            calendarTitle: e.calendar?.title ?? "?"
        )
    }

    private func describe(_ a: EKAlarm) -> String {
        if let d = a.absoluteDate { return "at \(stampFormatter.string(from: d))" }
        let total = Int(a.relativeOffset)
        let sign = total < 0 ? "-" : "+"
        let mins = abs(total) / 60
        return "\(sign)\(mins / 60)h\(String(format: "%02d", mins % 60))m from start (\(total)s)"
    }

    private static func name(of s: EKAuthorizationStatus) -> String {
        switch s {
        case .fullAccess: return "Full Access"
        case .writeOnly: return "Add Events Only (write-only) — cannot read events"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        default: return "Other (\(s.rawValue))"
        }
    }

    private static func name(of t: EKCalendarType) -> String {
        switch t {
        case .local: return "local"
        case .calDAV: return "CalDAV (iCloud)"
        case .exchange: return "Exchange"
        case .subscription: return "subscription"
        case .birthday: return "birthday"
        @unknown default: return "other"
        }
    }
}

struct TsujiIDCheckView: View {
    @StateObject private var check = TsujiIDCheck()
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                if check.hasRun {
                    Text(check.verdict)
                        .font(.headline)
                        .foregroundStyle(check.passed == true ? Color.green : Color.red)
                }
                Button {
                    check.run()
                    copied = false
                } label: {
                    Label(check.hasRun ? "Run check again" : "Run check", systemImage: "arrow.clockwise")
                }
                if check.needsAccess {
                    Button {
                        Task { await check.requestAccess() }
                    } label: {
                        Label("Allow Calendar access", systemImage: "calendar.badge.checkmark")
                    }
                }
                if check.hasRun {
                    Button {
                        UIPasteboard.general.string = check.report
                        copied = true
                    } label: {
                        Label(copied ? "Copied — paste it to Claude" : "Copy report", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                }
            } footer: {
                Text("Read-only. Nudge only looks at your Tsuji Plan calendar here — nothing in Calendar is changed. If access is off, turn on Full Access for Nudge in Settings → Privacy & Security → Calendars.")
            }
            .listRowBackground(Theme.surface)

            if check.hasRun {
                Section("Report") {
                    Text(check.report)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("Calendar ID check")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !check.hasRun { check.run() } }
    }
}
