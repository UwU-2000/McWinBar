import AppKit
import ApplicationServices

/// Brings a specific window to the front using the Accessibility API.
enum WindowActivator {

    /// Whether we have Accessibility permission. Optionally prompts the user.
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func activate(_ win: WindowInfo) {
        // 1. Bring the owning application forward.
        if let app = NSRunningApplication(processIdentifier: win.pid) {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        // 2. Find the exact window and raise it.
        let axWindows = AX.windows(pid: win.pid)
        guard !axWindows.isEmpty else { return }

        let target = bestMatch(in: axWindows, for: win) ?? axWindows[0]

        // Restore if minimized, then raise and focus.
        AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString,
                                     kCFBooleanFalse as CFTypeRef)
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString,
                                     kCFBooleanTrue as CFTypeRef)

        let appElement = AXUIElementCreateApplication(win.pid)
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, target)
    }

    /// Picks the Accessibility window matching the one we recorded.
    ///
    /// Title is the primary key: stacked/maximized windows of the same app share
    /// identical frames (so geometry alone can't tell them apart), but their
    /// titles differ. The CGWindow title is typically a prefix of the AX title
    /// (e.g. Chrome appends " - Google Chrome - <profile>"), so we rank exact,
    /// prefix, then substring matches. Geometry is only a tiebreaker and the
    /// fallback when titles are unavailable.
    private static func bestMatch(in elements: [AXUIElement], for win: WindowInfo) -> AXUIElement? {
        let want = win.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var best: AXUIElement?
        var bestScore = CGFloat.greatestFiniteMagnitude

        for el in elements {
            // Title rank (dominant term).
            var titleRank: CGFloat = 3   // no title info / no match
            if !want.isEmpty {
                let axTitle = AX.title(el)
                if axTitle == want { titleRank = 0 }
                else if axTitle.hasPrefix(want) { titleRank = 1 }
                else if axTitle.contains(want) { titleRank = 2 }
            } else {
                titleRank = 0            // rely purely on geometry
            }

            // Geometry distance (tiebreaker).
            var geom: CGFloat = 1_000_000
            if let f = AX.frame(el) {
                geom = abs(f.origin.x - win.bounds.origin.x)
                    + abs(f.origin.y - win.bounds.origin.y)
                    + abs(f.size.width - win.bounds.size.width)
                    + abs(f.size.height - win.bounds.size.height)
            }

            let score = titleRank * 10_000_000 + geom
            if score < bestScore {
                bestScore = score
                best = el
            }
        }
        return best
    }
}
