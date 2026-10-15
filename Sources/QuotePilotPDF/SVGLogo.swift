import AppKit
import CoreGraphics

/// An SVG logo, turned into a one-page PDF once, when it is imported. The PDF is what gets stored,
/// and the existing PDF logo path (`Logo.vector`) draws it, so the logo stays sharp at any size.
///
/// macOS 14 and later read SVG themselves (`NSImage`). Drawing that image into a PDF context keeps
/// its shapes, paths and text as PDF vector drawing, with no bitmap in between.
public enum SVGLogo {
    /// The page size for an SVG that has no size of its own and nothing to measure (the SVG default).
    public static let defaultSize = CGSize(width: 300, height: 150)

    /// The longest side the page may have, in points. A larger SVG is shrunk to this, still vector:
    /// PDF pages top out near 14,400 points, and a logo is only ever drawn a few hundred points wide.
    public static let largestSide: CGFloat = 5_000

    /// Whether a file is meant to be an SVG: it is named like one.
    public static func isSVG(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "svg"
    }

    /// Whether `data` reads as SVG text (an `<svg` tag somewhere in it), for data that comes without
    /// a file name, like the old tool's logo.
    public static func looksLikeSVG(_ data: Data) -> Bool {
        data.range(of: Data("<svg".utf8)) != nil
    }

    /// The SVG at `url` as a one-page PDF, or nil when macOS can't read it as an image. The page is
    /// the SVG's natural size, which comes from its `width` and `height`, or its `viewBox`, or the
    /// size of what it draws; `defaultSize` when it has none of those.
    public static func pdfData(from url: URL) -> Data? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let size = pageSize(forNaturalSize: image.size)
        var box = CGRect(origin: .zero, size: size)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil)
        else { return nil }
        context.beginPDFPage(nil)
        let graphics = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(in: box, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
        let pdf = data as Data
        // Only hand back something the logo path can use: one page with a shape.
        guard let provider = CGDataProvider(data: pdf as CFData),
              let document = CGPDFDocument(provider), document.numberOfPages == 1,
              let page = document.page(at: 1), !page.getBoxRect(.cropBox).isEmpty
        else { return nil }
        return pdf
    }

    /// The PDF page's size for an SVG of this natural size: `defaultSize` when it has no size,
    /// otherwise the size itself, kept in proportion and within `largestSide`.
    static func pageSize(forNaturalSize natural: CGSize) -> CGSize {
        guard natural.width.isFinite, natural.height.isFinite, natural.width > 0, natural.height > 0 else {
            return defaultSize
        }
        let shrink = min(1, largestSide / max(natural.width, natural.height))
        return CGSize(width: natural.width * shrink, height: natural.height * shrink)
    }
}
