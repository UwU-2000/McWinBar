import AppKit

/// Windows of a single application, grouped for one taskbar button.
struct AppGroup {
    let pid: pid_t
    let ownerName: String
    var windows: [WindowInfo]
    /// The front-most (currently-viewed) window of this app, from z-order.
    var frontWindowNumber: CGWindowID

    var icon: NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    var bundleID: String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}

enum Grouping {
    /// Groups a flat window list by owning app, preserving first-seen order.
    static func group(_ windows: [WindowInfo]) -> [AppGroup] {
        var order: [pid_t] = []
        var map: [pid_t: AppGroup] = [:]
        for w in windows {
            if var g = map[w.pid] {
                g.windows.append(w)
                map[w.pid] = g
            } else {
                order.append(w.pid)
                // Input is front-to-back z-order, so the first window we see for
                // a pid is that app's front-most (currently-viewed) window.
                map[w.pid] = AppGroup(pid: w.pid, ownerName: w.ownerName,
                                      windows: [w], frontWindowNumber: w.windowNumber)
            }
        }
        // Stable window order within each app (by window number ≈ creation
        // order) so thumbnails don't reshuffle on focus changes.
        return order.compactMap { pid in
            guard var g = map[pid] else { return nil }
            g.windows.sort { $0.windowNumber < $1.windowNumber }
            return g
        }
    }
}
