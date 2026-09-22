import AppKit
import ApplicationServices

/// Thin wrappers around the Accessibility API for reading/writing window geometry.
enum AX {
    static func windows(pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
              let arr = v as? [AXUIElement] else { return [] }
        return arr
    }

    static func title(_ el: AXUIElement) -> String {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &v)
        return (v as? String) ?? ""
    }

    static func subrole(_ el: AXUIElement) -> String {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXSubroleAttribute as CFString, &v)
        return (v as? String) ?? ""
    }

    static func isMinimized(_ el: AXUIElement) -> Bool {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXMinimizedAttribute as CFString, &v)
        return (v as? Bool) ?? false
    }

    static func isFullscreen(_ el: AXUIElement) -> Bool {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(el, "AXFullScreen" as CFString, &v)
        return (v as? Bool) ?? false
    }

    static func frame(_ el: AXUIElement) -> CGRect? {
        var pv: CFTypeRef?
        var sv: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &pv) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sv) == .success,
              let pvv = pv, let svv = sv,
              CFGetTypeID(pvv) == AXValueGetTypeID(),
              CFGetTypeID(svv) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(pvv as! AXValue, .cgPoint, &p),
              AXValueGetValue(svv as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    static func setPosition(_ el: AXUIElement, _ p: CGPoint) {
        var pp = p
        if let v = AXValueCreate(.cgPoint, &pp) {
            AXUIElementSetAttributeValue(el, kAXPositionAttribute as CFString, v)
        }
    }

    static func setSize(_ el: AXUIElement, _ s: CGSize) {
        var ss = s
        if let v = AXValueCreate(.cgSize, &ss) {
            AXUIElementSetAttributeValue(el, kAXSizeAttribute as CFString, v)
        }
    }
}
