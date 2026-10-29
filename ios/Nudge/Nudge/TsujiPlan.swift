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
}
