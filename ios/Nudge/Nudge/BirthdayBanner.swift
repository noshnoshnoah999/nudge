// BirthdayBanner.swift — Nudge (iOS + Mac)
//
// Home banner for birthdays from the iOS/macOS Birthdays calendar (Noah, 2026-10-18):
//   • on the day:            "Say happy birthday to Mum!"
//   • 1–3 days before:       "Mum's birthday is in 2 days" — a heads-up, matching the
//                            3-days-before / on-the-day birthday notifications.
// Each banner can be dismissed with ✕; a dismissal lasts for that day only, so a heads-up
// comes back the next morning (with the new count) and the on-the-day one still appears.
// Dismissals are per device (UserDefaults) — nothing here is synced or written to the cloud.
//
// Data comes from CalendarService.upcomingBirthdays, which needs Calendar access; without it
// the banner simply never shows.

import SwiftUI
import Combine

final class BirthdayBanners: ObservableObject {
    static let shared = BirthdayBanners()

    struct Item: Identifiable, Equatable {
        let id: String        // "<today yyyy-MM-dd>|<calendar title>" — dismissal key
        let name: String
        let daysAway: Int     // 0 = today
        let date: Date
    }

    @Published private(set) var items: [Item] = []
    @Published private var dismissed: Set<String> = []

    private let dismissedKey = "birthdayBannerDismissed"

    private init() {
        dismissed = Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }

    var visible: [Item] { items.filter { !dismissed.contains($0.id) } }

    /// Re-read the Birthdays calendar. Call on launch (after Calendar access is settled) and
    /// on every foreground — the day may have changed while Nudge was in the background.
    func reload() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let todayKey = Self.dayKey(today)
        items = CalendarService.shared.upcomingBirthdays(within: 4).compactMap { b in
            let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: b.date)).day ?? 0
            guard (0...3).contains(days) else { return nil }
            return Item(id: "\(todayKey)|\(b.title)", name: Self.name(from: b.title),
                        daysAway: days, date: b.date)
        }
        // Forget dismissals from earlier days so the stored set can't grow forever.
        let kept = dismissed.filter { $0.hasPrefix(todayKey + "|") }
        if kept != dismissed { dismissed = kept; save() }
    }

    func dismiss(_ item: Item) {
        dismissed.insert(item.id)
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(dismissed), forKey: dismissedKey)
    }

    private static func dayKey(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    /// The Birthdays calendar titles events "Mum's Birthday" / "Taku’s Birthday". Strip that
    /// suffix to get the name; anything unrecognised is shown as-is.
    static func name(from title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for suffix in ["’s Birthday", "'s Birthday", "’s birthday", "'s birthday", " Birthday", " birthday"] {
            if t.hasSuffix(suffix), t.count > suffix.count { return String(t.dropLast(suffix.count)) }
        }
        return t
    }
}

/// One banner row. Plain surface styling so it sits quietly on Home in every theme.
struct BirthdayBannerRow: View {
    let item: BirthdayBanners.Item
    let onDismiss: () -> Void

    private var headline: String {
        switch item.daysAway {
        case 0:  return "Say happy birthday to \(item.name)!"
        case 1:  return "\(item.name)'s birthday is tomorrow"
        default: return "\(item.name)'s birthday is in \(item.daysAway) days"
        }
    }

    private var subline: String {
        if item.daysAway == 0 { return "It's their birthday today." }
        let f = DateFormatter()
        f.dateFormat = "EEEE d MMM"
        return f.string(from: item.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.daysAway == 0 ? "gift.fill" : "gift")
                .font(.title3)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textMain)
                Text(subline).font(.caption).foregroundStyle(Theme.textMeta)
            }
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textMeta)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background {
            if Theme.minimal {
                Rectangle().fill(Theme.surface)
            } else {
                RoundedRectangle(cornerRadius: Theme.radius(14), style: .continuous).fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius(14), style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1))
            }
        }
    }
}
