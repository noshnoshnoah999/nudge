// ClaudeLink.swift — Nudge (iOS)
// "Claude - <prompt>" reminders → open claude.ai in an in-app browser
// (SFSafariViewController) with the prompt prefilled, using the user's own
// signed-in Safari session (their subscription). No API key, no automation:
// it's Apple's sandboxed Safari, so we only ever set the URL.

import SwiftUI
import SafariServices

enum ClaudeLink {
    /// Returns the prompt if the title looks like "Claude - …" / "Claude — …".
    static func prompt(from title: String) -> String? {
        let t = title.trimmingCharacters(in: .whitespaces)
        let pattern = "^[Cc]laude\\s*[-—–]\\s*(.+)$"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)),
              let r = Range(m.range(at: 1), in: t) else { return nil }
        let p = String(t[r]).trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? nil : p
    }

    /// A new-chat URL with the prompt prefilled.
    static func url(for prompt: String) -> URL? {
        var c = URLComponents(string: "https://claude.ai/new")
        c?.queryItems = [URLQueryItem(name: "q", value: prompt)]
        return c?.url
    }
}

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// SFSafariViewController wrapper — an in-app browser sheet.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    var tint: Color = Theme.violet

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let cfg = SFSafariViewController.Configuration()
        cfg.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.preferredControlTintColor = UIColor(tint)
        vc.dismissButtonStyle = .close
        return vc
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}
