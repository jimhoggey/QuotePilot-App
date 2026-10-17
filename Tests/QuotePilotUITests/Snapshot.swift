import AppKit
import PDFKit
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
            .environment(\.controlActiveState, .key)
            // Drawn for the 1x bitmap `capture` makes, not for the main screen's scale.
            .environment(\.displayScale, 1))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        guard let rep = capture(host) else { return nil }
        save(rep, name: name)
        return rep
    }

    /// `view` drawn at one pixel to the point, whatever the screens' backing scale: every test's
    /// pixel coordinates are points. (`bitmapImageRepForCachingDisplay` follows the main screen, so on
    /// a Retina display it is twice the size and every coordinate lands somewhere else.)
    static func capture(_ view: NSView) -> NSBitmapImageRep? {
        let bounds = view.bounds
        guard bounds.width >= 1, bounds.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width.rounded()),
                                         pixelsHigh: Int(bounds.height.rounded()), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = bounds.size
        view.cacheDisplay(in: bounds, to: rep)
        return rep
    }

    /// Page 1 of a PDF drawn on white, `scale` pixels to the point. Like `render`, it also saves a PNG
    /// when QP_SNAPSHOTS names a folder.
    static func renderPage(_ pdf: Data, scale: CGFloat = 2, name: String) -> NSBitmapImageRep? {
        // The document stays in a variable: a page can't be drawn once its document is gone.
        guard let document = PDFDocument(data: pdf), let page = document.page(at: 0) else { return nil }
        defer { withExtendedLifetime(document) {} }
        let box = page.bounds(for: .mediaBox)
        guard let context = CGContext(data: nil, width: Int(box.width * scale), height: Int(box.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let image = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        save(rep, name: name)
        return rep
    }

    private static func save(_ rep: NSBitmapImageRep, name: String) {
        if let folder = ProcessInfo.processInfo.environment["QP_SNAPSHOTS"],
           let png = rep.representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
        }
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

    /// How many pixels in the picture are the made-up SVG logo's magenta (`UIFixture.svgData`),
    /// within the top `rows` rows: nothing else in Quote Pilot is that colour.
    static func logoPixels(_ rep: NSBitmapImageRep, rows: Int? = nil) -> Int {
        guard let image = rep.cgImage else { return 0 }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var count = 0
        // The first row in memory is the top of the picture.
        for y in 0..<min(rows ?? height, height) {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Int(bytes[i]), g = Int(bytes[i + 1]), b = Int(bytes[i + 2])
                if r > g + 100, r > b + 50, b > g + 30 { count += 1 }
            }
        }
        return count
    }
}
