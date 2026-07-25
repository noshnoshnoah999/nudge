// WidgetBackgroundImageStore.swift — the user's custom widget background image,
// shared between the app and the widget extension.
//
// WHY THE KEYCHAIN (and not a file or UserDefaults):
// This project builds under a FREE Apple team, so App Groups are unavailable — there is
// no shared file container and no shared UserDefaults suite between the app and the
// widget extension. The Keychain access group is the only cross-target store available,
// and it's already proven here: it's how the widget reads the Supabase session
// (see AuthStore.swift, same access group).
//
// Storing image bytes in the Keychain is admittedly not what it was designed for, so the
// image is downscaled and JPEG-compressed hard before it's written. For Noah's use case
// this is tiny: the picture is a screenshot of an essentially flat black Home Screen
// page, which JPEG-compresses to a few kilobytes. `maxStoredBytes` is enforced so a
// mistakenly-picked photo (a real photograph, say) can't wedge a megabyte into the
// Keychain.
//
// PRIVACY: the image never leaves the device. It is not uploaded to Supabase and is not
// synced to the MacBook — that was an explicit requirement. It lives only in this
// device's Keychain, and `clear()` removes it.

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum WidgetBackgroundImageStore {
    private static let service = "uk.flouty.Nudge.widgetBackgroundImage"
    private static let account = "today"
    private static let accessGroup = "FMF6YAVA23.uk.flouty.Nudge.shared"

    /// Hard ceiling on what we're willing to put in the Keychain. A flat-wallpaper
    /// screenshot lands far below this; a real photograph would be rejected and the user
    /// told to pick a plain screenshot instead.
    static let maxStoredBytes = 256 * 1024   // 256 KB

    /// Longest edge the stored image is downscaled to. A widget is at most ~1200 px wide on
    /// the largest device, and the image is only ever stretched behind flat content, so
    /// there is no reason to keep more pixels than this.
    static let maxPixelDimension: CGFloat = 1200

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrAccessGroup as String: accessGroup]
    }

    // MARK: - Read (used by the widget extension)

    /// The raw stored JPEG bytes, or nil if the user hasn't set an image.
    static func loadData() -> Data? {
        var q = baseQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return data
    }

    #if canImport(UIKit)
    static func loadImage() -> UIImage? {
        guard let data = loadData() else { return nil }
        return UIImage(data: data)
    }
    #endif

    /// Whether a custom image is currently stored. Cheap-ish; still hits the Keychain, so
    /// don't call it in a tight loop.
    static var hasImage: Bool { loadData() != nil }

    // MARK: - Write (used by the app)

    #if canImport(UIKit)
    /// Downscale + compress, then store. Returns nil on success, or a human-readable reason
    /// on failure so the UI can explain what went wrong.
    @discardableResult
    static func save(_ image: UIImage) -> String? {
        guard let data = jpegData(for: image) else {
            return "Couldn't process that image. Try a different one."
        }
        guard data.count <= maxStoredBytes else {
            return "That image is too detailed to store (\(data.count / 1024) KB). "
                 + "Use a screenshot of an empty Home Screen page instead of a photo."
        }
        return write(data) ? nil : "Couldn't save the image to the Keychain."
    }

    /// Downscale so the longest edge is at most `maxPixelDimension`, then JPEG-encode.
    /// Stepping quality down lets a slightly busy image still fit rather than being rejected.
    private static func jpegData(for image: UIImage) -> Data? {
        let scaled = downscaled(image)
        for quality in [CGFloat(0.8), 0.6, 0.4, 0.25] {
            if let d = scaled.jpegData(compressionQuality: quality), d.count <= maxStoredBytes {
                return d
            }
        }
        return scaled.jpegData(compressionQuality: 0.2)
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxPixelDimension, longest > 0 else { return image }
        let factor = maxPixelDimension / longest
        let target = CGSize(width: (image.size.width * factor).rounded(),
                            height: (image.size.height * factor).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
    #endif

    private static func write(_ data: Data) -> Bool {
        // AfterFirstUnlock so the widget can read it while the device is locked — widget
        // timelines refresh without the user unlocking. Same reasoning as AuthStore.
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attrs as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add.merge(attrs) { a, _ in a }
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
