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

    /// On-screen windows first (front-to-back z-order), then windows that are
    /// off-screen but still real: minimized, or living on another Space (e.g.
    /// when some app is fullscreen). Without the second pass the taskbar would
    /// only show the current Space's windows.
    static func list() -> [WindowInfo] {
        let onScreen = query([.optionOnScreenOnly, .excludeDesktopElements],
                             requireTitle: false)
        var seen = Set(onScreen.map { $0.windowNumber })
        var result = onScreen
        // Off-screen pass: require a non-empty title, otherwise this picks up
        // apps' invisible buffer/helper windows that never appear on screen.
        for w in query([.optionAll, .excludeDesktopElements], requireTitle: true)
        where !seen.contains(w.windowNumber) {
            seen.insert(w.windowNumber)
            result.append(w)
        }
        return result
    }

    private static func query(_ options: CGWindowListOption,
                              requireTitle: Bool) -> [WindowInfo] {
        let myPid = getpid()
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // Only windows of real (Dock-visible) apps belong on a taskbar. System
        // agents like AuthenticationServices keep titled layer-0 windows that
        // are never user-facing and can't be focused.
        var isRegularApp: [pid_t: Bool] = [:]
        func regular(_ pid: pid_t) -> Bool {
            if let cached = isRegularApp[pid] { return cached }
            let v = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
            isRegularApp[pid] = v
            return v
        }

        var result: [WindowInfo] = []
        for w in raw {
            // Only the normal window layer (0). Menus, the Dock, overlays, etc.
            // live on other layers.
            guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != myPid else { continue }
            guard regular(pid) else { continue }
            guard let num = w[kCGWindowNumber as String] as? CGWindowID else { continue }

            let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
            if ignoredOwners.contains(owner) { continue }

            let title = (w[kCGWindowName as String] as? String) ?? ""
            if requireTitle && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                continue
            }

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
