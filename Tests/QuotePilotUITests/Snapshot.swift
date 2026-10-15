import AppKit
import SwiftUI

/// Renders a SwiftUI view through AppKit in an off-screen window, so text fields and pickers draw
/// as they really do. When QP_SNAPSHOTS names a folder, it also saves a PNG there for people to
/// look at.
@MainActor
enum Snapshot {
    static func render<V: View>(_ view: V, size: CGSize, name: String) -> NSBitmapImageRep? {
        _ = NSApplication.shared
        // An off-screen window is never the key window; draw as if it were, so title bars are navy.
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .light)
            .environment(\.controlActiveState, .key))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let folder = ProcessInfo.processInfo.environment["QP_SNAPSHOTS"],
           let png = rep.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
        return rep
    }

    /// True when the picture has at least three distinct colours: something was drawn.
    static func hasContent(_ rep: NSBitmapImageRep) -> Bool {
        var seen = Set<UInt32>()
        let stepX = max(1, rep.pixelsWide / 60), stepY = max(1, rep.pixelsHigh / 60)
        for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let key = UInt32(color.redComponent * 255) << 16 | UInt32(color.greenComponent * 255) << 8 | UInt32(color.blueComponent * 255)
                seen.insert(key)
                if seen.count >= 3 { return true }
            }
        }
        return false
    }
}
