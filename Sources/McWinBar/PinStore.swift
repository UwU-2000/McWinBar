import AppKit

/// Persists the user's pinned apps (by bundle identifier) in UserDefaults and
/// resolves them to launchable URLs / icons.
final class PinStore {
    static let shared = PinStore()
    private let key = "pinnedBundleIDs"

    private(set) var bundleIDs: [String]

    private init() {
        bundleIDs = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func isPinned(_ bundleID: String) -> Bool { bundleIDs.contains(bundleID) }

    func pin(_ bundleID: String) {
        guard !bundleID.isEmpty, !bundleIDs.contains(bundleID) else { return }
        bundleIDs.append(bundleID)
        save()
    }

    func unpin(_ bundleID: String) {
        bundleIDs.removeAll { $0 == bundleID }
        save()
    }

    private func save() {
        UserDefaults.standard.set(bundleIDs, forKey: key)
    }

    // MARK: - Resolution

    func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    func name(for bundleID: String) -> String {
        guard let url = url(for: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    func icon(for bundleID: String) -> NSImage? {
        guard let url = url(for: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
