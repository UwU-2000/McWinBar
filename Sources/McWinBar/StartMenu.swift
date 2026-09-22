import AppKit

/// Enumerates installed applications for the Start menu.
enum InstalledApps {
    private static let searchDirs = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities"
    ]

    /// (displayName, url) for every .app found, sorted by name.
    static func all() -> [(name: String, url: URL)] {
        let fm = FileManager.default
        var seen = Set<String>()
        var apps: [(String, URL)] = []
        for dir in searchDirs {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                let name = entry.replacingOccurrences(of: ".app", with: "")
                if seen.insert(name).inserted {
                    apps.append((name, url))
                }
            }
        }
        return apps.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }
}

/// A searchable list of installed apps shown from the Start button.
final class StartMenuController: NSViewController, NSSearchFieldDelegate {
    private let onLaunch: (URL) -> Void
    private let apps = InstalledApps.all()
    private var searchField: NSSearchField!
    private var listStack: NSStackView!

    init(onLaunch: @escaping (URL) -> Void) {
        self.onLaunch = onLaunch
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func loadView() {
        let width: CGFloat = 320
        let height: CGFloat = 440
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        searchField = NSSearchField()
        searchField.placeholderString = "Search apps…"
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        listStack = NSStackView()
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 2
        listStack.translatesAutoresizingMaskIntoConstraints = false

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(listStack)
        scroll.documentView = doc

        root.addSubview(searchField)
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),

            listStack.topAnchor.constraint(equalTo: doc.topAnchor),
            listStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            listStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])

        self.view = root
        reload(filter: "")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(searchField)
    }

    func controlTextDidChange(_ obj: Notification) {
        reload(filter: searchField.stringValue)
    }

    private func reload(filter: String) {
        listStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let f = filter.trimmingCharacters(in: .whitespaces)
        let matches = f.isEmpty
            ? apps
            : apps.filter { $0.name.localizedCaseInsensitiveContains(f) }

        for app in matches {
            let row = NSButton()
            row.title = "  " + app.name
            row.image = {
                let img = NSWorkspace.shared.icon(forFile: app.url.path)
                img.size = NSSize(width: 20, height: 20)
                return img
            }()
            row.imagePosition = .imageLeading
            row.alignment = .left
            row.isBordered = false
            row.setButtonType(.momentaryChange)
            row.contentTintColor = .labelColor
            row.target = self
            row.action = #selector(launch(_:))
            row.identifier = NSUserInterfaceItemIdentifier(app.url.path)
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalToConstant: 300).isActive = true
            listStack.addArrangedSubview(row)
        }
    }

    @objc private func launch(_ sender: NSButton) {
        guard let path = sender.identifier?.rawValue else { return }
        onLaunch(URL(fileURLWithPath: path))
    }
}
