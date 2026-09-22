import AppKit

/// A single on-screen window belonging to some application.
struct WindowInfo: Equatable {
    let windowNumber: CGWindowID
    let pid: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect

    /// Text shown on the taskbar button. Falls back to the app name when the
    /// window has no title (window titles require Screen Recording permission
    /// on recent macOS; without it `kCGWindowName` comes back empty).
    var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? ownerName : t
    }

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.windowNumber == rhs.windowNumber && lhs.title == rhs.title
    }
}

/// Enumerates the real, user-facing windows currently on screen.
enum WindowLister {
    /// Owners that are system UI, never real application windows.
    private static let ignoredOwners: Set<String> = [
        "Window Server", "Dock", "Control Center", "Notification Center",
        "Spotlight", "WindowManager", "Wallpaper", "Screenshot",
        "McWinBar" // our own app
    ]

    static func list() -> [WindowInfo] {
        let myPid = getpid()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var result: [WindowInfo] = []
        for w in raw {
            // Only the normal window layer (0). Menus, the Dock, overlays, etc.
            // live on other layers.
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPid else { continue }
            guard let num = w[kCGWindowNumber as String] as? CGWindowID else { continue }

            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            if ignoredOwners.contains(owner) { continue }

            let title = (w[kCGWindowName as String] as? String) ?? ""

            var bounds = CGRect.zero
            if let b = w[kCGWindowBounds as String] as? [String: Any],
               let r = CGRect(dictionaryRepresentation: b as CFDictionary) {
                bounds = r
            }
            // Skip tiny helper/utility windows (tooltips, status items, etc.).
            if bounds.width < 100 || bounds.height < 80 { continue }

            result.append(WindowInfo(windowNumber: num, pid: pid,
                                     ownerName: owner, title: title, bounds: bounds))
        }
        return result
    }
}
