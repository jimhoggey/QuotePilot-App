import AppKit
import CoreText
import ImageIO
import QuotePilotCore

/// Colours, fonts and logo for documents.
public struct PDFStyle {
    public static let ink = CGColor(srgbRed: 0x1F / 255, green: 0x2A / 255, blue: 0x44 / 255, alpha: 1)
    public static let muted = CGColor(srgbRed: 0x5E / 255, green: 0x67 / 255, blue: 0x7C / 255, alpha: 1)
    public static let rule = CGColor(srgbRed: 0xDD / 255, green: 0xE2 / 255, blue: 0xEA / 255, alpha: 1)

    public var accent: CGColor
    public var headingFontURL: URL?
    public var logo: Logo?

    public init(accentHex: String = "#0B6B66", headingFontURL: URL? = nil, logo: Logo? = nil) {
        accent = PDFStyle.color(hex: accentHex) ?? PDFStyle.color(hex: "#0B6B66")!
        self.headingFontURL = headingFontURL
        self.logo = logo
    }

    /// The brand's look, with its logo and font files found in the library's Assets folder.
    public init(brand: Brand, assetsFolder: URL?) {
        let fontURL = brand.headingFontFile.flatMap { name in assetsFolder?.appendingPathComponent(name) }
        let logo = brand.logoFile.flatMap { name in assetsFolder.flatMap { Logo(url: $0.appendingPathComponent(name)) } }
        self.init(accentHex: brand.accentHex, headingFontURL: fontURL, logo: logo)
    }

    /// "#0B6B66" → an sRGB colour, or nil if it isn't six hex digits.
    public static func color(hex: String) -> CGColor? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                       green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255,
                       alpha: 1)
    }

    /// The brand's heading font, or the system font in semibold when there's none or it won't load.
    func heading(_ size: CGFloat) -> CTFont {
        if let url = headingFontURL,
           let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
           let first = descriptors.first {
            return CTFontCreateWithFontDescriptor(first, size, nil)
        }
        return NSFont.systemFont(ofSize: size, weight: .semibold) as CTFont
    }

    func body(_ size: CGFloat, weight: NSFont.Weight = .regular) -> CTFont {
        NSFont.systemFont(ofSize: size, weight: weight) as CTFont
    }
}

/// A logo from a PNG or JPG (bitmap) or a PDF (stays sharp at any size). An SVG logo is a PDF by the
/// time it gets here: `SVGLogo` converts it when it is imported.
public enum Logo {
    case bitmap(CGImage)
    case vector(CGPDFPage)

    public init?(url: URL) {
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
            self = .vector(page)
        } else {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            self = .bitmap(image)
        }
    }

    var size: CGSize {
        switch self {
        case .bitmap(let image): return CGSize(width: image.width, height: image.height)
        case .vector(let page): return page.getBoxRect(.cropBox).size
        }
    }

    /// Draws inside `rect` (PDF coordinates), keeping its shape, against the left edge.
    func draw(in rect: CGRect, context: CGContext) {
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let drawn = CGRect(x: rect.minX, y: rect.minY + (rect.height - size.height * scale) / 2,
                           width: size.width * scale, height: size.height * scale)
        switch self {
        case .bitmap(let image):
            context.draw(image, in: drawn)
        case .vector(let page):
            let box = page.getBoxRect(.cropBox)
            context.saveGState()
            context.translateBy(x: drawn.minX, y: drawn.minY)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            context.restoreGState()
        }
    }
}
