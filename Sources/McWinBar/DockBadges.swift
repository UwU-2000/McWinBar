import AppKit
import ApplicationServices

/// Reads notification badges from the Dock's accessibility tree. Even while the
/// Dock is hidden, its process exposes each app tile with an "AXStatusLabel"
/// attribute containing the badge text (e.g. unread count). Keyed by the tile's
/// title (the app's display name).
enum DockBadges {
    static func read() -> [String: String] {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication
                  .runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [:] }

        let dockEl = AXUIElementCreateApplication(dock.processIdentifier)
        var result: [String: String] = [:]
        collectBadges(dockEl, into: &result, depth: 0)
        return result
    }

    /// Walks the Dock AX tree (shallow) collecting title -> badge for tiles.
    private static func collectBadges(_ element: AXUIElement,
                                      into result: inout [String: String],
                                      depth: Int) {
        if depth > 3 { return }

        var badgeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, "AXStatusLabel" as CFString, &badgeRef)
        if let badge = badgeRef as? String, !badge.isEmpty {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
            if let title = titleRef as? String, !title.isEmpty {
                result[title] = badge
            }
        }

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString,
                                            &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        for child in children {
            collectBadges(child, into: &result, depth: depth + 1)
        }
    }
}
