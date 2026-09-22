import AppKit

/// A Windows-style taskbar entry: a flat, full-height cell with an icon + label,
/// a subtle hover/active highlight box, and an accent underline indicating the
/// app is running (a longer bar when it has multiple windows).
final class TaskbarEntryView: NSView {
    var group: AppGroup?
    var bundleID: String?
    var appURL: URL?
    var isPinned = false
    var isActive = false
    var badge: String?

    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    var onExit: (() -> Void)?
    var contextMenu: NSMenu?

    private let iconView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var hovered = false
    private var tracking: NSTrackingArea?

    private var isRunning: Bool { group != nil }
    private var windowCount: Int { group?.windows.count ?? 0 }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(iconView)
        addSubview(label)

        let maxLabel = label.widthAnchor.constraint(lessThanOrEqualToConstant: 150)
        maxLabel.priority = .defaultHigh

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            maxLabel
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Configuration

    func configure(icon: NSImage?, name: String) {
        if let icon = icon {
            icon.size = NSSize(width: 18, height: 18)
            iconView.image = icon
        }
        if let badge = badge, !badge.isEmpty {
            let s = NSMutableAttributedString(
                string: name + "  ",
                attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium),
                             .foregroundColor: NSColor.labelColor])
            s.append(NSAttributedString(
                string: badge,
                attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold),
                             .foregroundColor: NSColor.systemRed]))
            label.attributedStringValue = s
        } else {
            label.stringValue = name
            label.textColor = .labelColor
        }
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Highlight box (active > hover), Windows-style flat translucent fill.
        let fillAlpha: CGFloat = isActive ? 0.20 : (hovered ? 0.12 : 0.0)
        if fillAlpha > 0 {
            let box = bounds.insetBy(dx: 1, dy: 2)
            NSColor.white.withAlphaComponent(fillAlpha).setFill()
            NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        }

        // Running indicator: one underline segment per window, laid out
        // horizontally. The front (currently-viewed) window is drawn in the
        // accent color; the rest use a muted, CSS ":disabled"-style grey.
        if isRunning, let group = group {
            let wins = group.windows
            let n = max(1, wins.count)
            let gap: CGFloat = 3
            let maxTotal = bounds.width - 12
            var seg: CGFloat = 16
            if CGFloat(n) * seg + CGFloat(n - 1) * gap > maxTotal {
                seg = max(4, (maxTotal - CGFloat(n - 1) * gap) / CGFloat(n))
            }
            let total = CGFloat(n) * seg + CGFloat(n - 1) * gap
            var x = bounds.midX - total / 2
            let y: CGFloat = 2.5
            let h: CGFloat = 3

            for w in wins {
                let isFront = (w.windowNumber == group.frontWindowNumber)
                let color = isFront ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor
                color.setFill()
                NSBezierPath(roundedRect: NSRect(x: x, y: y, width: seg, height: h),
                             xRadius: 1.5, yRadius: 1.5).fill()
                x += seg + gap
            }
        }
    }

    // MARK: - Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        needsDisplay = true
        onHover?()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        needsDisplay = true
        onExit?()
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if bounds.contains(p) { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = contextMenu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}
