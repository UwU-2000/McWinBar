import AppKit

/// A button that reports mouse enter/exit so we can drive hover previews.
final class HoverButton: NSButton {
    var group: AppGroup?          // set when the app has open windows
    var bundleID: String?         // pin identity
    var appURL: URL?              // launch target when there are no windows
    var isPinned: Bool = false
    var onHover: (() -> Void)?
    var onExit: (() -> Void)?

    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseExited(with event: NSEvent) { onExit?() }

    // Ensure right-click reliably shows the pin/unpin menu even inside a
    // non-activating panel.
    override func rightMouseDown(with event: NSEvent) {
        if let menu = menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }
}

/// Root view for the popover that reports enter/exit so the preview stays open
/// while the pointer is over it.
final class TrackingView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// A clickable thumbnail cell (preview image + title) for one window.
final class ThumbCell: NSButton {
    var window_: WindowInfo?
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeAlways],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }
}

/// Shows the windows of an app group as a row of clickable thumbnails.
final class ThumbnailGridController: NSViewController {
    private let group: AppGroup
    private let onSelect: (WindowInfo) -> Void
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    var onPeek: ((WindowInfo) -> Void)?
    var onPeekEnd: (() -> Void)?

    init(group: AppGroup, onSelect: @escaping (WindowInfo) -> Void) {
        self.group = group
        self.onSelect = onSelect
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let thumbW: CGFloat = 200
        let root = TrackingView()
        root.onEnter = { [weak self] in self?.onEnter?() }
        root.onExit = { [weak self] in self?.onExit?() }

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false

        for win in group.windows {
            row.addArrangedSubview(makeCell(for: win, width: thumbW))
        }

        root.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            row.topAnchor.constraint(equalTo: root.topAnchor),
            row.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
        self.view = root
    }

    private func makeCell(for win: WindowInfo, width: CGFloat) -> NSView {
        let cell = ThumbCell()
        cell.window_ = win
        cell.imagePosition = .imageOnly
        cell.bezelStyle = .regularSquare
        cell.isBordered = true
        cell.target = self
        cell.action = #selector(cellClicked(_:))
        // Only entering a cell drives the peek; we intentionally don't hide on
        // cell exit so moving between adjacent thumbnails swaps smoothly rather
        // than flickering. The peek hides when the whole popover is dismissed.
        cell.onEnter = { [weak self] in self?.onPeek?(win) }

        let image = Thumbnailer.capture(windowNumber: win.windowNumber, maxDimension: width)
            ?? NSRunningApplication(processIdentifier: win.pid)?.icon
        cell.image = image
        cell.imageScaling = .scaleProportionallyUpOrDown

        let label = NSTextField(labelWithString: shortTitle(win.displayTitle))
        label.font = NSFont.systemFont(ofSize: 10)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        let col = NSStackView(views: [cell, label])
        col.orientation = .vertical
        col.alignment = .centerX
        col.spacing = 4
        col.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            cell.widthAnchor.constraint(equalToConstant: width),
            cell.heightAnchor.constraint(equalToConstant: width * 0.62),
            label.widthAnchor.constraint(equalToConstant: width)
        ])
        return col
    }

    private func shortTitle(_ s: String, max: Int = 30) -> String {
        s.count <= max ? s : String(s.prefix(max - 1)) + "…"
    }

    @objc private func cellClicked(_ sender: ThumbCell) {
        guard let win = sender.window_ else { return }
        onSelect(win)
    }
}
