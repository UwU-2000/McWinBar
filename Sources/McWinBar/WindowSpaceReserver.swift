import AppKit

/// macOS has no public API for a third-party app to reserve screen space the
/// way the Dock/menu bar do. This is a best-effort equivalent: any standard
/// window that overlaps the bar's region is lifted so its bottom edge rests on
/// top of the bar (shrinking only when the window is too tall to fit above it).
///
/// Only the main screen (where the bar lives) is handled.
final class WindowSpaceReserver {
    private let barHeight: CGFloat

    init(barHeight: CGFloat) {
        self.barHeight = barHeight
    }

    func enforce() {
        guard AXIsProcessTrusted() else { return }
        guard let screen = NSScreen.main, let primary = NSScreen.screens.first else { return }

        let primaryH = primary.frame.height
        // Convert Cocoa (bottom-left) geometry to Quartz/AX (top-left) space.
        let barTopQuartz = primaryH - (screen.frame.minY + barHeight)
        let screenTopQuartz = primaryH - screen.frame.maxY
        let topInsetCocoa = screen.frame.maxY - screen.visibleFrame.maxY   // menu bar
        let usableTopQuartz = screenTopQuartz + topInsetCocoa
        let minX = screen.frame.minX
        let maxX = screen.frame.maxX

        let mePid = NSRunningApplication.current.processIdentifier

        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != mePid {

            for win in AX.windows(pid: app.processIdentifier) {
                guard AX.subrole(win) == (kAXStandardWindowSubrole as String) else { continue }
                guard !AX.isMinimized(win) else { continue }
                // Never touch fullscreen windows: they live in their own Space
                // where the bar doesn't apply, and resizing them corrupts the
                // fullscreen/tiled layout.
                guard !AX.isFullscreen(win) else { continue }
                guard var frame = AX.frame(win) else { continue }

                // Must be on this screen (horizontal overlap) and have sane size.
                if frame.maxX <= minX || frame.minX >= maxX { continue }
                if frame.width < 40 || frame.height < 40 { continue }

                let bottom = frame.origin.y + frame.size.height
                if bottom <= barTopQuartz + 1 { continue } // already clear of the bar

                var newY = barTopQuartz - frame.size.height
                if newY < usableTopQuartz {
                    // Too tall to simply move up: clamp to the top and shrink.
                    newY = usableTopQuartz
                    let newHeight = barTopQuartz - usableTopQuartz
                    if newHeight > 40 {
                        frame.size.height = newHeight
                        AX.setSize(win, frame.size)
                    }
                }
                frame.origin.y = newY
                AX.setPosition(win, frame.origin)
            }
        }
    }
}
