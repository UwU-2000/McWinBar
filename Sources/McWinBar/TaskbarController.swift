import AppKit
import Carbon.HIToolbox

/// Owns the always-on-top panel at the bottom of the screen and keeps its
/// contents in sync with the list of open windows.
final class TaskbarController: NSObject {
    private let barHeight: CGFloat = 44
    private var panel: NSPanel!
    private var stack: NSStackView!            // app-group buttons (left)
    private var startButton: NSButton!
    private var tick_: Timer?
    private var lastWindows: [WindowInfo] = []

    // Start menu
    private var startPopover: NSPopover?
    private var startHotKey: HotKey?

    // Stable launch-order for running apps (first launched = leftmost).
    private var appOrder: [pid_t: Int] = [:]
    private var orderSeq = 0

    // Aero-peek preview + notification badges (from the hidden Dock).
    private let peek = PreviewPeek()
    private var badges: [String: String] = [:]   // app title -> badge text

    // Right-hand system tray
    private let battery = BatteryView()
    private let clock = ClockView()
    private let desktopToggler = DesktopToggler()
    private var desktopButton: NSButton!

    // Screen-space reservation
    private lazy var reserver = WindowSpaceReserver(barHeight: barHeight)

    // Hover preview
    private var popover: NSPopover?
    private var popoverPid: pid_t?
    private var closeWork: DispatchWorkItem?

    override init() {
        super.init()
        buildPanel()
        startObserving()
        tick()

        // Ctrl+Esc opens the Start menu (mirrors Windows; not a macOS default).
        startHotKey = HotKey(keyCode: UInt32(kVK_Escape),
                             modifiers: UInt32(controlKey)) { [weak self] in
            self?.toggleStartMenu()
        }
    }

    // MARK: - UI

    private func buildPanel() {
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let f = screen.frame
        let rect = NSRect(x: f.minX, y: f.minY, width: f.width, height: barHeight)

        panel = NSPanel(contentRect: rect,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.92)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let content = panel.contentView!

        // --- Right tray -------------------------------------------------
        desktopButton = NSButton()
        desktopButton.title = ""
        desktopButton.image = NSImage(systemSymbolName: "rectangle.on.rectangle",
                                      accessibilityDescription: "Show Desktop")
        desktopButton.imagePosition = .imageOnly
        desktopButton.bezelStyle = .texturedRounded
        desktopButton.setButtonType(.momentaryChange)
        desktopButton.isBordered = true
        desktopButton.toolTip = "Show / Hide Desktop"
        desktopButton.target = self
        desktopButton.action = #selector(toggleDesktop)

        let separator = NSBox()
        separator.boxType = .separator

        // --- Start button (far left) -----------------------------------
        startButton = NSButton()
        startButton.image = NSImage(systemSymbolName: "circle.grid.3x3.fill",
                                    accessibilityDescription: "Start")
        startButton.imagePosition = .imageOnly
        startButton.bezelStyle = .texturedRounded
        startButton.setButtonType(.momentaryChange)
        startButton.isBordered = true
        startButton.toolTip = "Start"
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.target = self
        startButton.action = #selector(toggleStartMenu)

        let tray = NSStackView(views: [battery, clock, separator, desktopButton])
        tray.orientation = .horizontal
        tray.alignment = .centerY
        tray.spacing = 10
        tray.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        tray.translatesAutoresizingMaskIntoConstraints = false
        tray.setContentHuggingPriority(.required, for: .horizontal)
        tray.setContentCompressionResistancePriority(.required, for: .horizontal)

        // --- Left window list ------------------------------------------
        let scroll = NSScrollView()
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc

        content.addSubview(startButton)
        content.addSubview(scroll)
        content.addSubview(tray)

        NSLayoutConstraint.activate([
            tray.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            tray.topAnchor.constraint(equalTo: content.topAnchor),
            tray.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            startButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            startButton.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            startButton.widthAnchor.constraint(equalToConstant: 40),
            startButton.heightAnchor.constraint(equalToConstant: 30),

            scroll.leadingAnchor.constraint(equalTo: startButton.trailingAnchor, constant: 4),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.trailingAnchor.constraint(equalTo: tray.leadingAnchor),

            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.topAnchor.constraint(equalTo: doc.topAnchor),
            stack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.heightAnchor.constraint(equalToConstant: barHeight),

            battery.widthAnchor.constraint(equalToConstant: 56),
            separator.heightAnchor.constraint(equalToConstant: 24),
            desktopButton.widthAnchor.constraint(equalToConstant: 34),
            desktopButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        panel.orderFrontRegardless()
    }

    // MARK: - Periodic update

    @objc private func tick() {
        clock.refresh()
        battery.refresh()
        refreshWindows()
        refreshBadges()
        reserver.enforce()
    }

    /// Pull notification badges from the (hidden) Dock and surface them on our
    /// buttons, flashing any app whose badge just appeared or changed.
    private func refreshBadges() {
        let newBadges = DockBadges.read()
        if newBadges == badges { return }

        let changed = newBadges.filter { badges[$0.key] != $0.value }.map { $0.key }
        badges = newBadges
        rebuildButtons()
        for title in changed { flashButton(appTitle: title) }
    }

    private func flashButton(appTitle: String) {
        guard let entry = stack.arrangedSubviews.compactMap({ $0 as? TaskbarEntryView })
            .first(where: { $0.group?.ownerName == appTitle }) else { return }
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 1.0
        anim.toValue = 0.3
        anim.duration = 0.4
        anim.autoreverses = true
        anim.repeatCount = 3
        entry.layer?.add(anim, forKey: "notifyFlash")
    }

    @objc private func refreshWindows() {
        let windows = WindowLister.list()
        if windows == lastWindows { return }
        lastWindows = windows
        rebuildButtons()
    }

    /// Rebuilds the taskbar: pinned apps first (in pin order), then running
    /// apps that aren't pinned. Pinned apps that are running merge with their
    /// window group; pinned apps that aren't running show as launchers.
    private func rebuildButtons() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // Assign a stable launch-order sequence to any newly-seen app, then
        // sort by it so buttons keep a fixed position regardless of focus.
        let groups = Grouping.group(lastWindows)
        for g in groups where appOrder[g.pid] == nil {
            appOrder[g.pid] = orderSeq
            orderSeq += 1
        }
        // Drop entries for apps that are no longer running.
        let livePids = Set(groups.map { $0.pid })
        appOrder = appOrder.filter { livePids.contains($0.key) }

        let ordered = groups.sorted { (appOrder[$0.pid] ?? 0) < (appOrder[$1.pid] ?? 0) }

        var groupByBundle: [String: AppGroup] = [:]
        for g in ordered {
            if let b = g.bundleID, groupByBundle[b] == nil { groupByBundle[b] = g }
        }

        var usedBundles = Set<String>()

        // 1. Pinned apps, in the user's pin order.
        for bundle in PinStore.shared.bundleIDs {
            usedBundles.insert(bundle)
            if let g = groupByBundle[bundle] {
                stack.addArrangedSubview(makeEntry(g, pinned: true, active: g.pid == frontPid))
            } else {
                stack.addArrangedSubview(makeLauncher(bundleID: bundle))
            }
        }

        // 2. Running, non-pinned apps, in launch order.
        for g in ordered {
            if let b = g.bundleID, usedBundles.contains(b) { continue }
            stack.addArrangedSubview(makeEntry(g, pinned: false, active: g.pid == frontPid))
        }
    }

    private func makeEntry(_ group: AppGroup, pinned: Bool, active: Bool) -> TaskbarEntryView {
        let entry = TaskbarEntryView()
        entry.translatesAutoresizingMaskIntoConstraints = false
        entry.group = group
        entry.bundleID = group.bundleID
        entry.isPinned = pinned
        entry.isActive = active
        entry.badge = badges[group.ownerName]
        entry.configure(icon: group.icon, name: group.ownerName)
        entry.heightAnchor.constraint(equalToConstant: barHeight).isActive = true
        entry.contextMenu = contextMenu(bundleID: group.bundleID, pinned: pinned)
        entry.onClick = {
            if let win = group.windows.first { WindowActivator.activate(win) }
        }
        entry.onHover = { [weak self, weak entry] in
            guard let self = self, let entry = entry, let g = entry.group else { return }
            self.showThumbnails(for: g, from: entry)
        }
        entry.onExit = { [weak self] in self?.scheduleClose() }
        return entry
    }

    private func makeLauncher(bundleID: String) -> TaskbarEntryView {
        let entry = TaskbarEntryView()
        entry.translatesAutoresizingMaskIntoConstraints = false
        entry.bundleID = bundleID
        entry.isPinned = true
        entry.appURL = PinStore.shared.url(for: bundleID)
        entry.configure(icon: PinStore.shared.icon(for: bundleID),
                        name: PinStore.shared.name(for: bundleID))
        entry.heightAnchor.constraint(equalToConstant: barHeight).isActive = true
        entry.contextMenu = contextMenu(bundleID: bundleID, pinned: true)
        let url = entry.appURL
        entry.onClick = { if let url = url { NSWorkspace.shared.open(url) } }
        return entry
    }

    private func contextMenu(bundleID: String?, pinned: Bool) -> NSMenu? {
        guard let bundleID = bundleID else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(
            title: pinned ? "Unpin from Taskbar" : "Pin to Taskbar",
            action: #selector(togglePin(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = bundleID
        menu.addItem(item)
        return menu
    }

    @objc private func togglePin(_ sender: NSMenuItem) {
        guard let bundleID = sender.representedObject as? String else { return }
        if PinStore.shared.isPinned(bundleID) {
            PinStore.shared.unpin(bundleID)
        } else {
            PinStore.shared.pin(bundleID)
        }
        rebuildButtons()
    }

    @objc private func toggleDesktop() {
        desktopToggler.toggle()
        let name = desktopToggler.desktopShown ? "rectangle.on.rectangle.fill" : "rectangle.on.rectangle"
        desktopButton.image = NSImage(systemSymbolName: name, accessibilityDescription: "Show Desktop")
    }

    // MARK: - Start menu

    @objc private func toggleStartMenu() {
        if let pop = startPopover, pop.isShown {
            pop.close()
            startPopover = nil
            return
        }
        let vc = StartMenuController { [weak self] url in
            NSWorkspace.shared.open(url)
            self?.startPopover?.close()
            self?.startPopover = nil
        }
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = vc
        // Activate so the search field can receive keystrokes.
        NSApp.activate(ignoringOtherApps: true)
        pop.show(relativeTo: startButton.bounds, of: startButton, preferredEdge: .maxY)
        startPopover = pop
    }

    // MARK: - Hover preview

    private func showThumbnails(for group: AppGroup, from button: NSView) {
        cancelClose()
        if popoverPid == group.pid, popover != nil { return }
        closePopoverImmediately()

        let vc = ThumbnailGridController(group: group) { [weak self] win in
            WindowActivator.activate(win)
            self?.closePopoverImmediately()
        }
        vc.onEnter = { [weak self] in self?.cancelClose() }
        vc.onExit = { [weak self] in self?.scheduleClose() }
        vc.onPeek = { [weak self] win in self?.peek.requestShow(win) }
        vc.onPeekEnd = { [weak self] in self?.peek.hide() }

        let pop = NSPopover()
        pop.behavior = .applicationDefined
        pop.animates = false
        pop.contentViewController = vc
        pop.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)

        popover = pop
        popoverPid = group.pid
    }

    private func scheduleClose() {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.closePopoverImmediately() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func cancelClose() {
        closeWork?.cancel()
        closeWork = nil
    }

    private func closePopoverImmediately() {
        cancelClose()
        peek.hide()
        popover?.close()
        popover = nil
        popoverPid = nil
    }

    // MARK: - Observers

    private func startObserving() {
        tick_ = Timer.scheduledTimer(timeInterval: 1.0, target: self,
                                     selector: #selector(tick),
                                     userInfo: nil, repeats: true)

        let wsCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            wsCenter.addObserver(self, selector: #selector(refreshWindows),
                                 name: name, object: nil)
        }
    }
}
