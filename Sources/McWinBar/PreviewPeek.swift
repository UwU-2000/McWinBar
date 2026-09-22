import AppKit

/// Windows "Aero Peek"-style large preview: hovering a window thumbnail shows a
/// near-fullscreen snapshot of that window, centered on screen.
///
/// Captures run on a background queue (they can be slow for big windows) and a
/// generation counter drops results that arrive after the user has moved on, so
/// quickly sweeping across thumbnails stays smooth.
final class PreviewPeek {
    private var panel: NSPanel?
    private var showWork: DispatchWorkItem?
    private var generation = 0
    private let captureQueue = DispatchQueue(label: "taskbar.peek.capture", qos: .userInitiated)

    /// Schedule the preview after a short sustained hover.
    func requestShow(_ win: WindowInfo, delay: TimeInterval = 0.12) {
        showWork?.cancel()
        let gen = bumpGeneration()
        let work = DispatchWorkItem { [weak self] in self?.capture(win, gen: gen) }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {
        showWork?.cancel()
        showWork = nil
        _ = bumpGeneration()          // invalidate any in-flight capture
        panel?.orderOut(nil)
    }

    // MARK: - Internals

    private func bumpGeneration() -> Int {
        generation += 1
        return generation
    }

    private func capture(_ win: WindowInfo, gen: Int) {
        let number = win.windowNumber
        captureQueue.async { [weak self] in
            let img = Thumbnailer.capture(windowNumber: number, maxDimension: 1400)
            DispatchQueue.main.async {
                guard let self = self, gen == self.generation, let img = img else { return }
                self.present(img)
            }
        }
    }

    private func present(_ img: NSImage) {
        guard let screen = NSScreen.main else { return }
        let vis = screen.visibleFrame
        let maxW = vis.width * 0.85
        let maxH = vis.height * 0.85
        let scale = min(maxW / img.size.width, maxH / img.size.height, 1)
        let size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
        let origin = NSPoint(x: vis.midX - size.width / 2,
                             y: vis.midY - size.height / 2 + 16)

        let p: NSPanel
        if let existing = panel {
            p = existing
        } else {
            p = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .stationary]
            let iv = NSImageView()
            iv.imageScaling = .scaleAxesIndependently
            iv.wantsLayer = true
            iv.layer?.cornerRadius = 8
            iv.layer?.masksToBounds = true
            p.contentView = iv
            panel = p
        }

        (p.contentView as? NSImageView)?.image = img
        p.setFrame(NSRect(origin: origin, size: size), display: true)
        p.orderFrontRegardless()
    }
}
