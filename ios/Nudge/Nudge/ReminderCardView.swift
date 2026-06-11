// ReminderCardView.swift — Nudge (iOS)
// One reminder card, shared by the main list and the Today view.
// Modern, flat-tinted look: a strong title, a soft "due" pill (gentle coral when
// overdue rather than flooding the card), muted metadata chips, and a tappable
// link button. Tuned to feel calm and current, not cramped.

import SwiftUI

struct ReminderCardView: View {
    @EnvironmentObject var store: NudgeStore
    @EnvironmentObject var settings: AppSettings
    @Environment(\.openURL) private var openURL
    let reminder: Reminder
    var onEdit: () -> Void
    @State private var claudeURL: IdentifiableURL?
    @State private var isPolishing = false
    @State private var showReschedule = false
    @State private var dragX: CGFloat = 0

    private var radius: CGFloat { settings.compact ? 14 : 18 }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Delete affordance revealed as the card slides left.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.coral)
                .overlay(alignment: .trailing) {
                    Image(systemName: "trash.fill").font(.headline).foregroundStyle(.white)
                        .padding(.trailing, 28)
                        .opacity(Double(min(1, -dragX / 70)))
                }
                .opacity(dragX < 0 ? 1 : 0)

            cardBody
                .offset(x: dragX)
                .simultaneousGesture(swipeGesture)
        }
        .sheet(item: $claudeURL) { SafariView(url: $0.url, tint: settings.accent) }
        .sheet(isPresented: $showReschedule) { RescheduleOptionsView(reminder: reminder).environmentObject(store) }
        .contextMenu {
            Button { store.toggleComplete(reminder) } label: { Label("Complete", systemImage: "checkmark.circle") }
            Button { store.snooze(reminder, minutes: 30) } label: { Label("Snooze 30 min", systemImage: "moon.zzz") }
            Button { store.snooze(reminder, minutes: 60) } label: { Label("Snooze 1 hour", systemImage: "moon.zzz") }
            Button { showReschedule = true } label: { Label("Reschedule…", systemImage: "calendar.badge.clock") }
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { withAnimation { store.deleteReminder(reminder) } } label: { Label("Delete", systemImage: "trash") }
        }
    }

    /// Swipe left past a threshold to delete; a short pull snaps back.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in
                // Engage only for a clearly horizontal swipe; let vertical scroll pass.
                if dragX == 0 && abs(v.translation.width) < abs(v.translation.height) { return }
                dragX = max(min(v.translation.width, 0), -120)
            }
            .onEnded { v in
                if v.translation.width < -90 {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    withAnimation(.easeIn(duration: 0.18)) { dragX = -600 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { store.deleteReminder(reminder) }
                } else {
                    withAnimation(Theme.spring) { dragX = 0 }
                }
            }
    }

    private var cardBody: some View {
        let r = reminder
        let overdue = store.isOverdue(r)
        let compact = settings.compact
        let claudeP = ClaudeLink.prompt(from: r.title)
        let done = r.isCompleted

        return HStack(alignment: .top, spacing: compact ? 12 : 14) {
            Button {
                store.toggleComplete(r)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(done ? Theme.sage : (overdue ? Theme.coral : Theme.textMeta.opacity(0.5)))
                    .symbolEffect(.bounce, value: done)
            }
            .buttonStyle(PressableStyle(scale: 0.8))
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: compact ? 5 : 7) {
                // Title — the hero of the card.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if claudeP != nil {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(settings.accent)
                    }
                    Text(claudeP ?? displayTitle(r))
                        .font(.system(size: compact ? 15 : 16, weight: .semibold))
                        .foregroundStyle(done ? Theme.textMeta : Theme.textMain)
                        .strikethrough(done, color: Theme.textMeta)
                        .lineSpacing(1.5)
                        .lineLimit(compact ? 2 : nil)
                        .fixedSize(horizontal: false, vertical: compact ? false : true)
                }

                // Primary metadata: when · which list · how important.
                if dueLabel(r) != nil || store.list(for: r.listId) != nil
                    || r.priorityOrNormal != "normal" {
                    HStack(spacing: 7) {
                        if let label = dueLabel(r) { dueChip(label, overdue: overdue) }
                        if let l = store.list(for: r.listId) {
                            HStack(spacing: 5) {
                                Circle().fill(Color(hex: l.color)).frame(width: 7, height: 7)
                                Text(l.name).font(.caption.weight(.medium)).foregroundStyle(Theme.textMeta)
                            }
                        }
                        if r.priorityOrNormal == "high" { priorityPill("High", color: Theme.coral) }
                        else if r.priorityOrNormal == "low" { priorityPill("Low", color: Theme.textMeta) }
                    }
                }

                // Secondary indicators: repeat · subtasks · early · open-link · photo · location · source.
                if hasIndicators(r) {
                    HStack(spacing: 12) {
                        if let rec = r.recurrence, rec.freq != "none" {
                            metaIcon("repeat", text: recurText(rec), color: settings.accent)
                        }
                        if let subs = r.subtasks, !subs.isEmpty {
                            let done = subs.filter { $0.done }.count
                            metaIcon("checklist", text: "\(done)/\(subs.count)",
                                     color: done == subs.count ? Theme.sage : Theme.textMeta)
                        }
                        if (r.remindBefore ?? 0) > 0 {
                            metaIcon("bell.badge", text: earlyText(r.remindBefore ?? 0), color: Theme.textMeta)
                        }
                        if let u = r.url, !u.isEmpty { linkButton(u) }
                        if ImageStore.hasImages(for: r.id) { metaIcon("photo", text: nil) }
                        if let loc = r.location, !loc.isEmpty {
                            Button { openMaps(loc, r.lat, r.lng) } label: {
                                metaIcon("mappin.and.ellipse", text: loc)
                            }
                            .buttonStyle(.plain)
                        }
                        if let badge = sourceBadge(r.source) {
                            Text(badge).font(.caption2.weight(.bold)).foregroundStyle(settings.accent)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(settings.accentSoft, in: Capsule())
                        }
                    }
                }

                if let p = claudeP { askClaudeButton(p).padding(.top, 2) }
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            Spacer(minLength: 0)
        }
        .padding(compact ? 13 : 15)
        .background(overdue ? Theme.coral.opacity(0.07) : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
            .stroke(overdue ? Theme.coral.opacity(0.22) : Theme.hairline, lineWidth: 1))
        .cardElevation(compact ? 6 : 11, y: compact ? 2 : 5, opacity: done ? 0.02 : (compact ? 0.05 : 0.07))
        .opacity(done ? 0.6 : 1)
    }

    // MARK: - Chips & pieces

    private func dueChip(_ label: String, overdue: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: overdue ? "exclamationmark.circle.fill" : "clock")
                .font(.system(size: 10, weight: .semibold))
            Text(label).font(.caption.weight(.semibold))
        }
        .foregroundStyle(overdue ? Theme.coral : Theme.textMeta)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(overdue ? Theme.coral.opacity(0.14) : Theme.surfaceAlt.opacity(0.55), in: Capsule())
    }

    private func priorityPill(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2.weight(.bold)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.14), in: Capsule())
    }

    private func metaIcon(_ system: String, text: String?, color: Color = Theme.textMeta) -> some View {
        HStack(spacing: 4) {
            Image(systemName: system).font(.system(size: 11, weight: .medium))
            if let t = text { Text(t).font(.caption.weight(.medium)).lineLimit(1) }
        }
        .foregroundStyle(color)
    }

    private func linkButton(_ s: String) -> some View {
        Button { if let u = URL(string: s) { openURL(u) } } label: {
            HStack(spacing: 4) {
                Image(systemName: "link").font(.system(size: 10, weight: .semibold))
                Text(linkLabel(s)).font(.caption.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(settings.accent)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .background(settings.accentSoft, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private func askClaudeButton(_ p: String) -> some View {
        Button {
            guard !isPolishing else { return }
            isPolishing = true
            Task {
                let polished = await PromptPolisher.polish(p)   // on-device, falls back to raw
                UIPasteboard.general.string = polished
                if let u = ClaudeLink.url(for: polished) { claudeURL = IdentifiableURL(url: u) }
                isPolishing = false
            }
        } label: {
            HStack(spacing: 5) {
                if isPolishing {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text("Polishing…")
                } else {
                    Image(systemName: "sparkles")
                    Text("Ask Claude")
                }
            }
            .font(.caption.weight(.bold)).foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(settings.accentGrad, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Helpers

    private func linkLabel(_ s: String) -> String {
        if let h = URL(string: s)?.host { return h.replacingOccurrences(of: "www.", with: "") }
        return "Open link"
    }

    private func openMaps(_ name: String, _ lat: Double?, _ lng: Double?) {
        let q = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let s = (lat != nil && lng != nil)
            ? "http://maps.apple.com/?ll=\(lat!),\(lng!)&q=\(q)"
            : "http://maps.apple.com/?q=\(q)"
        if let u = URL(string: s) { openURL(u) }
    }

    private func hasIndicators(_ r: Reminder) -> Bool {
        (r.recurrence != nil && r.recurrence?.freq != "none")
            || r.url?.isEmpty == false
            || (r.location?.isEmpty == false)
            || (r.subtasks?.isEmpty == false)
            || ((r.remindBefore ?? 0) > 0)
            || sourceBadge(r.source) != nil
            || ImageStore.hasImages(for: r.id)
    }

    /// "30m early", "1h early", "1d early" — compact label for an advance reminder.
    private func earlyText(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440)d early" }
        if minutes % 60 == 0 { return "\(minutes / 60)h early" }
        return "\(minutes)m early"
    }

    /// Badge text for auto-generated reminders. Manual *and* Apple-synced reminders
    /// (Control Centre / Siri captures) get no badge — they're just normal reminders.
    private func sourceBadge(_ source: String?) -> String? {
        switch source {
        case "finance":    return "Finance"
        case "studytrack": return "Study"
        case nil, "manual", "apple": return nil
        default:           return "Auto"
        }
    }
}
