// GroupCardView.swift — Nudge (iOS)
// A collapsed "group card": one row standing in for several related reminders, to clear
// clutter. Tap the header to expand and reveal every member (each a normal ReminderCardView);
// tap again to collapse. Long-press → Ungroup (non-destructive — just breaks the group apart).

import SwiftUI

/// A row in a reminder list: either a single reminder or a collapsed group of them.
enum ListItem: Identifiable {
    case single(Reminder)
    case group(id: String, title: String, items: [Reminder])

    var id: String {
        switch self {
        case .single(let r):        return "r-\(r.id)"
        case .group(let id, _, _):  return "g-\(id)"
        }
    }
}

struct GroupCardView: View {
    @EnvironmentObject var store: NudgeStore
    @EnvironmentObject var settings: AppSettings
    let groupId: String
    let title: String
    let items: [Reminder]
    var onEdit: (Reminder) -> Void

    @State private var expanded = false

    private var radius: CGFloat { settings.compact ? 14 : 18 }
    private var count: Int { items.count }

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? (settings.compact ? 8 : 10) : 0) {
            header
            if expanded {
                ForEach(items) { r in
                    ReminderCardView(reminder: r) { onEdit(r) }
                        .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)),
                                                removal: .opacity))
                }
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(Theme.spring) { expanded.toggle() }
        } label: {
            HStack(spacing: settings.compact ? 12 : 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(settings.accentSoft)
                        .frame(width: 34, height: 34)
                    Image(systemName: expanded ? "folder.fill" : "folder")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(settings.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: settings.compact ? 15 : 16, weight: .semibold))
                        .foregroundStyle(Theme.textMain)
                        .lineLimit(1)
                    Text(expanded ? "Tap to collapse" : "\(count) reminder\(count == 1 ? "" : "s") · tap to open")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textMeta)
                }
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(settings.accent)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(settings.accentSoft, in: Capsule())
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textMeta)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
            .padding(settings.compact ? 13 : 15)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.hairline, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            Button {
                withAnimation(Theme.spring) { store.ungroup(groupId) }
            } label: { Label("Ungroup", systemImage: "rectangle.split.3x1") }
        }
    }
}
