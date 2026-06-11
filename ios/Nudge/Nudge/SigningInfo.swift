// SigningInfo.swift — Nudge
// Reads the app's own provisioning-profile expiry so we can warn before the
// free-team 7-day signing lapses (after which the app won't launch).

import Foundation

enum SigningInfo {
    /// Expiration date from the embedded provisioning profile, if any.
    static func expiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1) else { return nil }
        // The profile is a CMS blob with an embedded XML plist — slice it out.
        guard let s = raw.range(of: "<?xml")?.lowerBound ?? raw.range(of: "<plist")?.lowerBound,
              let e = raw.range(of: "</plist>")?.upperBound else { return nil }
        let plistStr = String(raw[s..<e])
        guard let pdata = plistStr.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: pdata, options: [], format: nil) as? [String: Any],
              let exp = plist["ExpirationDate"] as? Date else { return nil }
        return exp
    }

    /// Whole days until signing expires (nil if unknown, e.g. Simulator).
    static var daysLeft: Int? {
        guard let e = expiry() else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: e).day
    }
}
