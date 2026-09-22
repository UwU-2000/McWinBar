import AppKit

/// Captures a scaled-down image of a specific on-screen window for hover
/// previews. Real window content requires Screen Recording permission; without
/// it macOS returns a blank/desktop image.
enum Thumbnailer {
    static func capture(windowNumber: CGWindowID, maxDimension: CGFloat = 240) -> NSImage? {
        guard let cg = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowNumber,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else { return nil }

        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        guard w >= 1, h >= 1 else { return nil }

        let scale = min(maxDimension / w, maxDimension / h, 1)
        let size = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        return NSImage(cgImage: cg, size: size)
    }
}
