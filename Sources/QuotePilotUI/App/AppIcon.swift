import AppKit
import SwiftUI

/// The Dock icon: the quote icon's pixel art, large, on a teal tile with a raised edge.
public struct AppIconView: View {
    let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        let tile = size * 0.82
        ZStack {
            RoundedRectangle(cornerRadius: tile * 0.2)
                .fill(Win95.desktop)
                .frame(width: tile, height: tile)
                .overlay(
                    RoundedRectangle(cornerRadius: tile * 0.2)
                        .strokeBorder(Win95.highlight.opacity(0.6), lineWidth: max(1, size / 64))
                )
            PixelIconView(.quote, size: tile * 0.75)
        }
        .frame(width: size, height: size)
    }
}

public enum AppIcon {
    /// Writes an `.iconset` folder for `iconutil`: every size macOS asks for, drawn by `AppIconView`.
    @MainActor
    public static func writeIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let renderer = ImageRenderer(content: AppIconView(size: CGFloat(pixels)))
                renderer.scale = 1
                guard let image = renderer.cgImage,
                      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
                else { throw CocoaError(.fileWriteUnknown) }
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try png.write(to: folder.appendingPathComponent(name))
            }
        }
    }
}
