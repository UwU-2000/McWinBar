import AppKit
import IOKit.ps

// MARK: - Battery data

struct BatteryStatus {
    var percent: Int
    var charging: Bool
    var present: Bool
}

enum Battery {
    static func read() -> BatteryStatus {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            return BatteryStatus(percent: 0, charging: false, present: false)
        }
        for src in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, src)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            // Only consider an internal battery.
            let type = desc[kIOPSTypeKey] as? String
            if type != nil && type != kIOPSInternalBatteryType { continue }

            let cur = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maxCap = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let state = desc[kIOPSPowerSourceStateKey] as? String ?? ""
            let isCharging = (desc[kIOPSIsChargingKey] as? Bool)
                ?? (state == kIOPSACPowerValue)
            let percent = maxCap > 0 ? Int((Double(cur) / Double(maxCap) * 100).rounded()) : 0
            return BatteryStatus(percent: min(100, max(0, percent)),
                                 charging: isCharging, present: true)
        }
        return BatteryStatus(percent: 0, charging: false, present: false)
    }
}

// MARK: - Battery view (percentage drawn inside the icon)

final class BatteryView: NSView {
    private var status = BatteryStatus(percent: 0, charging: false, present: false)

    override var intrinsicContentSize: NSSize { NSSize(width: 56, height: 26) }

    func refresh() {
        status = Battery.read()
        isHidden = !status.present
        toolTip = status.present
            ? "\(status.percent)%\(status.charging ? " – charging" : "")"
            : nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard status.present else { return }

        let bodyW: CGFloat = 40, bodyH: CGFloat = 18
        let originX: CGFloat = 3
        let originY = (bounds.height - bodyH) / 2
        let body = NSRect(x: originX, y: originY, width: bodyW, height: bodyH)

        // Outline
        let outline = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        outline.lineWidth = 1
        NSColor.labelColor.setStroke()
        outline.stroke()

        // Positive terminal nub
        let nub = NSRect(x: body.maxX + 0.5, y: originY + bodyH * 0.28,
                         width: 2.5, height: bodyH * 0.44)
        NSColor.labelColor.setFill()
        NSBezierPath(roundedRect: nub, xRadius: 1, yRadius: 1).fill()

        // Charge fill
        let inner = body.insetBy(dx: 2, dy: 2)
        let fillW = inner.width * CGFloat(status.percent) / 100.0
        if fillW > 0 {
            let fillRect = NSRect(x: inner.minX, y: inner.minY,
                                  width: fillW, height: inner.height)
            let color: NSColor = status.charging
                ? .systemGreen
                : (status.percent <= 20 ? .systemRed : .systemGreen)
            color.setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2).fill()
        }

        // Percentage number inside the body
        let text = "\(status.percent)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: body.midX - size.width / 2,
                            y: body.midY - size.height / 2)
        text.draw(at: point, withAttributes: attrs)

        // Small charging bolt on the left edge
        if status.charging,
           let bolt = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: "charging") {
            let boltSize = NSSize(width: 8, height: 8)
            let boltRect = NSRect(x: body.minX - 1, y: body.midY - boltSize.height / 2,
                                  width: boltSize.width, height: boltSize.height)
            NSColor.labelColor.set()
            bolt.isTemplate = true
            bolt.draw(in: boltRect)
        }
    }
}

// MARK: - Clock (date + time, two lines)

final class ClockView: NSTextField {
    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d, yyyy"; return f
    }()

    convenience init() {
        self.init(labelWithString: "")
        isBezeled = false
        isEditable = false
        drawsBackground = false
        alignment = .center
        maximumNumberOfLines = 2
        lineBreakMode = .byClipping
        font = NSFont.systemFont(ofSize: 10, weight: .medium)
        cell?.wraps = true
        refresh()
    }

    func refresh() {
        let now = Date()
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineSpacing = 0
        let s = NSMutableAttributedString(
            string: timeFmt.string(from: now) + "\n",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
                         .paragraphStyle: para])
        s.append(NSAttributedString(
            string: dateFmt.string(from: now).uppercased(),
            attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .medium),
                         .foregroundColor: NSColor.secondaryLabelColor,
                         .paragraphStyle: para]))
        attributedStringValue = s
        toolTip = DateFormatter.localizedString(from: now, dateStyle: .full, timeStyle: .medium)
    }
}

// MARK: - Show / Hide Desktop toggle

/// Mirrors the Windows taskbar "Show desktop" button: first click hides every
/// visible app to reveal the desktop, second click restores exactly those apps.
final class DesktopToggler {
    private var hiddenApps: [NSRunningApplication] = []
    private(set) var desktopShown = false

    func toggle() {
        if desktopShown {
            hiddenApps.forEach { $0.unhide() }
            hiddenApps.removeAll()
            desktopShown = false
        } else {
            let me = NSRunningApplication.current
            let apps = NSWorkspace.shared.runningApplications.filter {
                $0.activationPolicy == .regular
                    && $0.processIdentifier != me.processIdentifier
                    && !$0.isHidden
            }
            apps.forEach { $0.hide() }
            hiddenApps = apps
            desktopShown = true
        }
    }
}
