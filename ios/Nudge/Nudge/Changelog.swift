// Changelog.swift — Nudge (iOS)
// The in-app update log shown in Settings → What's New.
// To add a release: prepend a new ChangelogEntry to `entries` (newest first).

import SwiftUI

struct ChangelogEntry: Identifiable {
    var id: String { version }
    let version: String
    let title: String
    let date: String
    let added: [String]
    let changed: [String]
}

enum Changelog {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(
            version: "2.25", title: "Catch a thought", date: "25 Jun 2026",
            added: [
                "New Quick Catch: tap the Nudge button in Control Centre, type a thought, and that's it — Claude reads it and picks a smart date & time, working around your calendar events and the days you're already busy",
                "Nothing is scheduled behind your back: a quick confirmation screen shows the suggested time (with a one-line reason) so you can tweak it or just tap Add",
                "No API key? It still works — a built-in planner drops the thought into a free slot tomorrow"
            ],
            changed: [
                "The Control Centre button now opens Quick Catch instead of the full reminder form (the full form is still on Siri & Shortcuts as \"Add to Nudge\")"
            ]),
        ChangelogEntry(
            version: "2.24", title: "Calendar on the timetable", date: "24 Jun 2026",
            added: [
                "Your real Calendar events now show on the Timetable — timed events appear as green 'busy' blocks behind your reminders, and all-day events as chips along the top, so you can drag reminders around your actual day"
            ],
            changed: [
                "Stale alerts are suppressed: if you complete a reminder on another device, the Mac no longer banners it (while Nudge is open) — including daily repeats that have already rolled to tomorrow"
            ]),
        ChangelogEntry(
            version: "2.23", title: "Rewards & end-of-day AI tidy-up", date: "24 Jun 2026",
            added: [
                "A satisfying complete animation — a gold border traces the reminder, it slides away to the left, and the rest of the list springs up to fill the gap (turn the sound & haptics off in Settings)",
                "End-of-day AI carry-over: each night at 23:50 Claude reviews what you didn't finish and rolls only the important ones to the next day — your nightly & repeating routines are never touched",
                "A glowing red banner the next morning shows what was moved and what was left, with reasons. Full history of the last month lives in Settings → Carry-Over History"
            ],
            changed: []),
        ChangelogEntry(
            version: "2.22", title: "Siri & Shortcuts", date: "23 Jun 2026",
            added: [
                "Control Nudge with Siri and the Shortcuts app: \"Add a reminder to Nudge\", \"What's due today in Nudge\", and complete a reminder by name",
                "These work as Shortcuts actions too — build automations like a morning \"what's due\" readout or arriving-home triggers"
            ],
            changed: []),
        ChangelogEntry(
            version: "2.21", title: "AI Smart Reschedule", date: "23 Jun 2026",
            added: [
                "Smart Reschedule can now use Claude — add your Anthropic API key in Settings and it spreads your overdue reminders intelligently around your calendar (falls back to the built-in planner with no key)"
            ],
            changed: [
                "Settings now matches your colour theme instead of a plain white page"
            ]),
        ChangelogEntry(
            version: "2.20", title: "Calendar-aware scheduling & birthdays", date: "22 Jun 2026",
            added: [
                "Nudge reads your Calendar: scheduling or rescheduling onto an event warns you first, and Smart Reschedule avoids your busy times",
                "Birthday reminders — a heads-up three days before and on the morning of each birthday, from your iOS Birthdays calendar"
            ],
            changed: [
                "Clearer date calendar in the reminder editor — today stands out (bold + ring)",
                "Timetable: reminders at the same time now sit side by side instead of hiding behind one another"
            ]),
        ChangelogEntry(
            version: "2.19", title: "Routines, pins & cleaner notifications", date: "20 Jun 2026",
            added: [
                "Completing a repeating routine now leaves a record in your Completed list (it still repeats)",
                "Search bar on the Completed list"
            ],
            changed: [
                "Pinned reminders and the Today list sort earliest-first (chronological)",
                "Notifications redesigned Apple-Reminders style — plain title, list, notes; no emoji clutter",
                "\"Claude - …\" reminders file into the Claude list automatically"
            ]),
        ChangelogEntry(
            version: "2.18", title: "Stability", date: "19 Jun 2026",
            added: [],
            changed: [
                "Fixed a crash when tapping a reminder notification while the app was fully closed"
            ]),
        ChangelogEntry(
            version: "2.17", title: "Overdue page & safer cleanup", date: "18 Jun 2026",
            added: [
                "New Overdue tab — reminders from before today live here. Anything due today stays on the Today tab until midnight, then moves over",
                "Clean Up (Settings) — swipe a row, or tap Select, to bulk-delete reminders you don't need"
            ],
            changed: [
                "Today now shows only today's reminders (overdue has its own tab)",
                "Remove duplicates now shows you exactly what it'll remove and waits for you to confirm — and always keeps an unfinished copy",
                "Fixed a cleanup bug that could delete the very copy it just kept"
            ]),
        ChangelogEntry(
            version: "2.16", title: "Notifications that just work", date: "18 Jun 2026",
            added: [
                "\"Make Ginger Shots\" is now a weekly routine, and a \"Buy Ginger Shot Ingredients\" reminder is auto-created 2 days before — it follows along if the date moves"
            ],
            changed: [
                "Completing a reminder from its notification now sticks — even when the app was fully closed",
                "Completing on one device clears the alert on your other device",
                "The Mac can now turn notifications on",
                "The progress widget's Today count now matches the app"
            ]),
        ChangelogEntry(
            version: "2.15", title: "Payday, routines & tidy-up", date: "14 Jun 2026",
            added: [
                "Buy reminders auto-schedule to your next payday, with a payday Home section and one payday notification",
                "Nightly routine check-in (KP / Epiduo) — miss one and Nudge asks you the next morning",
                "Type \"buy\" in a title and the reminder drops straight into Shopping as you type"
            ],
            changed: [
                "Completed reminders older than 3 weeks now clear themselves automatically"
            ]),
        ChangelogEntry(
            version: "2.14", title: "Stability fixes", date: "14 Jun 2026",
            added: [],
            changed: [
                "Fixed not being able to edit a reminder's title on iPhone (no keyboard appeared)",
                "Face ID no longer glitches or sticks when opening the app",
                "On Mac, the lock no longer re-asks for Touch ID every time you switch apps (Stage Manager)",
                "Fixed duplicate reminders from Apple sync — and the app no longer recreates them",
                "Smoother, less glitchy scrolling"
            ]),
        ChangelogEntry(
            version: "2.13", title: "Smart Reschedule preview", date: "13 Jun 2026",
            added: [
                "Smart Reschedule now shows a preview of every move before it applies — tap any to leave it where it is"
            ],
            changed: [
                "Rescheduled reminders keep their own time of day (or a sensible time guessed from the title)",
                "Overdue cards have a clearer coral border",
                "The \"expires in X days\" banner can be dismissed, and only comes back when it's urgent",
                "Triage is easier to find — tap the status line on Home"
            ]),
        ChangelogEntry(
            version: "2.12", title: "Timetable & per-reminder reschedule", date: "10 Jun 2026",
            added: [
                "Timetable — a draggable day-by-day schedule (calendar icon up top, or it opens after Smart Reschedule). Drag a reminder up/down to change its time",
                "Reschedule any reminder: long-press it → Reschedule (smart suggestion or pick your own)"
            ],
            changed: [
                "Pop-up sheets now fill edge-to-edge (no more white borders)"
            ]),
        ChangelogEntry(
            version: "2.11", title: "Notification & dashboard polish", date: "9 Jun 2026",
            added: [
                "Reschedule from a notification — opens the app with a smart suggestion (shows the exact new day/time) or pick your own",
                "Quick-complete button on the Home 'Next up' card"
            ],
            changed: [
                "Notifications now show the reminder's notes, due time and location",
                "Home shows more reminders when the window is bigger (great on Mac)"
            ]),
        ChangelogEntry(
            version: "2.10", title: "Stays installed", date: "9 Jun 2026",
            added: [
                "Nudge now warns you a couple of days before its free-install access expires, so you can reinstall before it stops opening",
                "Your Mac auto-reinstalls it every 5 days in the background (when it's connected)"
            ],
            changed: []),
        ChangelogEntry(
            version: "2.9", title: "Bug fixes", date: "9 Jun 2026",
            added: [],
            changed: [
                "Fixed 'Done today' being inflated and widgets wrongly showing all-complete (sync was re-stamping completed items with today's date)"
            ]),
        ChangelogEntry(
            version: "2.8", title: "Sections in lists", date: "9 Jun 2026",
            added: [
                "Sections (headers) inside a list — open a list, tap Add section",
                "Drag reminders between sections (and out to ungrouped)",
                "Each section shows a count; delete a section to ungroup its reminders"
            ],
            changed: []),
        ChangelogEntry(
            version: "2.7", title: "Cleanup, Face ID & motion", date: "9 Jun 2026",
            added: [
                "Face ID / Touch ID lock — turn it on in Settings → Privacy",
                "Remove duplicates — Settings → Maintenance cleans up identical reminders on both Nudge and Apple"
            ],
            changed: [
                "Smart Reschedule now animates reminders into their new days"
            ]),
        ChangelogEntry(
            version: "2.6", title: "Sync fixes", date: "9 Jun 2026",
            added: [],
            changed: [
                "Fixed Apple Reminders sync duplicating everything on each sync",
                "Fixed reminders disappearing and reappearing after completing",
                "Sync now re-links matching reminders by content instead of creating copies"
            ]),
        ChangelogEntry(
            version: "2.5", title: "Completed history", date: "9 Jun 2026",
            added: [
                "A history of everything you've completed, grouped by day — open it from the Done-today card or Lists → Completed",
                "Tap the check on any item to restore it"
            ],
            changed: []),
        ChangelogEntry(
            version: "2.4", title: "Home dashboard & fresh icon", date: "9 Jun 2026",
            added: [
                "New Home tab — an at-a-glance dashboard: today's progress, your next reminder, and key stats (overdue, due today, this week, done)",
                "Tap any stat to jump straight to it"
            ],
            changed: [
                "Brand-new app icon — the 'nudge' ripple, in the warm brown theme"
            ]),
        ChangelogEntry(
            version: "2.3", title: "Nudge on your Mac", date: "8 Jun 2026",
            added: [
                "Nudge now runs as a Mac app (Mac Catalyst) — same reminders, in a window on your Mac",
                "Notifications, Apple Reminders sync, photos and Ask Claude all work on the Mac too"
            ],
            changed: [
                "Control Centre quick-add stays iPhone-only (Mac uses its own widgets)"
            ]),
        ChangelogEntry(
            version: "2.2", title: "Sharper triage & a nicer form", date: "7 Jun 2026",
            added: [
                "Hourly repeat, and an \"End repeat\" date so a series can stop",
                "Triage now surfaces only the reminders you keep avoiding (auto-moved 3+ times) — not all 30",
                "Reschedule history already lets you Undo any run (Settings → Overdue)"
            ],
            changed: [
                "Smart Reschedule is now manual — tap it from Today or Triage; no more automatic morning sweep",
                "The new/edit reminder screen redesigned to match the app — warm theme, rounded type, animations"
            ]),
        ChangelogEntry(
            version: "2.1", title: "Smart Reschedule", date: "7 Jun 2026",
            added: [
                "Smart Reschedule: spreads your overdue pile across the coming week — weekends carry more, important & oldest first, weekday evenings vs weekend daytimes",
                "Runs automatically each day and shows you a report of what moved (with Undo)",
                "Or tap it yourself from Today or inside Triage",
                "Reschedule history (Settings → Overdue) — see every run it's ever made, with each reminder's old → new date, and Undo any run",
                "Turn the daily auto-sweep on/off in Settings → Overdue"
            ],
            changed: [
                "Overdue reminders no longer rot — they always move forward"
            ]),
        ChangelogEntry(
            version: "2.0", title: "A whole new look", date: "6 Jun 2026",
            added: [
                "Bottom tabs: Today · Upcoming · Lists · Search — jump around instead of one long scroll",
                "Colour themes (Mocha, Sage, Slate, Rose, Lavender, Graphite, Ocean) in Settings",
                "Lots more animation — sliding tabs, smooth transitions, springy taps"
            ],
            changed: [
                "Full redesign to a clean, single-colour look inspired by StudyTrack",
                "Flat tinted cards, big header, faster startup"
            ]),
        ChangelogEntry(
            version: "1.7", title: "Places & reminders that reach you", date: "6 Jun 2026",
            added: [
                "Location: search an address with a map picker, like Apple Reminders",
                "Tap a reminder's location to open it in Apple Maps",
                "A daily 9am notification digest of what's overdue and due today"
            ],
            changed: [
                "Notifications now reach you even when reminders are already overdue"
            ]),
        ChangelogEntry(
            version: "1.6", title: "Ask Claude from reminders", date: "6 Jun 2026",
            added: [
                "Reminders that start with \"Claude - \" show an Ask Claude button",
                "It opens claude.ai inside Nudge with your prompt ready to send, using your own login — no account switch",
                "Saving a new \"Claude - \" reminder starts the chat automatically",
                "Your quick note is auto-polished into a clearer prompt first — on-device (Apple Intelligence), private, free"
            ],
            changed: [
                "\"Claude - \" reminders show a ✦ and display just the prompt"
            ]),
        ChangelogEntry(
            version: "1.5", title: "Lighter, denser, yours", date: "5 Jun 2026",
            added: [
                "Appearance settings: Light / Dark / System theme",
                "Pick your accent colour (8 options)",
                "Compact mode — fits far more reminders on screen",
                "Collapse a section (tap its header) to fold away the overdue pile"
            ],
            changed: [
                "Light theme by default, with a cleaner colour palette",
                "Denser reminder cards so you scroll less"
            ]),
        ChangelogEntry(
            version: "1.4", title: "Customise your reminders", date: "5 Jun 2026",
            added: [
                "Repeat reminders — daily/weekly/monthly/yearly, every N; completing one creates the next automatically",
                "Time zone — pin a reminder to another country's clock",
                "Attach a link and a location (tap the pin to open Maps)",
                "Attach photos to a reminder (stored on this device)",
                "Tap the greeting card to jump to a focused Today view"
            ],
            changed: [
                "Reminder cards now show repeat / link / location / photo badges"
            ]),
        ChangelogEntry(
            version: "1.3", title: "Widgets & Control Centre", date: "4 Jun 2026",
            added: [
                "Home-screen widgets: Overdue, Today's Progress, Today list, Quick Add",
                "Control Centre control to jump straight into adding a reminder"
            ],
            changed: [
                "Widgets and the app stay in sync automatically"
            ]),
        ChangelogEntry(
            version: "1.2", title: "Notifications & a fresh look", date: "4 Jun 2026",
            added: [
                "Reminder notifications with Complete and Snooze buttons",
                "Brand-new app icon (bell + spark)"
            ],
            changed: [
                "Full visual redesign — polished light and dark themes",
                "Fixed text that was invisible in dark mode",
                "Lots of new animations throughout"
            ]),
        ChangelogEntry(
            version: "1.1", title: "Apple Reminders sync", date: "4 Jun 2026",
            added: [
                "Two-way sync with a dedicated Nudge list in Apple Reminders"
            ],
            changed: [
                "New reminders open the keyboard instantly and default to today, +1 hour"
            ]),
        ChangelogEntry(
            version: "1.0", title: "Nudge for iOS", date: "2 Jun 2026",
            added: [
                "Native app: fast capture, the 3-stage triage, and cloud sync with the web app"
            ],
            changed: [])
    ]
}

struct ChangelogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Changelog.entries) { entry in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.title).font(.headline.weight(.bold)).foregroundStyle(Theme.textMain)
                            Spacer()
                            Text("v\(entry.version)")
                                .font(.caption.weight(.bold)).foregroundStyle(Theme.violet)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Theme.violetSoft, in: Capsule())
                        }
                        Text(entry.date).font(.caption).foregroundStyle(Theme.textMeta)

                        if !entry.added.isEmpty {
                            label("New", color: Theme.sage)
                            ForEach(entry.added, id: \.self) { bullet($0, symbol: "plus.circle.fill", color: Theme.sage) }
                        }
                        if !entry.changed.isEmpty {
                            label("Changed", color: Theme.violet)
                            ForEach(entry.changed, id: \.self) { bullet($0, symbol: "wand.and.stars", color: Theme.violet) }
                        }
                    }
                    .padding(16)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                    .cardElevation(10, y: 4, opacity: 0.06)
                }
            }
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
        .navigationTitle("What's New")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.heavy)).tracking(0.6).foregroundStyle(color)
            .padding(.top, 2)
    }
    private func bullet(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).font(.caption).foregroundStyle(color).padding(.top, 1)
            Text(text).font(.subheadline).foregroundStyle(Theme.textMain)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
