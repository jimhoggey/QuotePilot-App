import AppKit
import CoreText
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

/// Fonts that ship with macOS, for tests that need a real variable font. The repo is public, so no
/// font file is copied into it.
enum SystemFonts {
    /// The usual places for a variable font, best first. Each has a Weight axis and named instances.
    static let variableCandidates = ["SFNS.ttf", "SFNSItalic.ttf", "NewYork.ttf", "SFCompact.ttf"]
        .map { URL(fileURLWithPath: "/System/Library/Fonts/\($0)") }
    static let georgia = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Georgia.ttf")

    /// A variable font on this Mac with its weights: the plain weight instances (no width or grade
    /// variants), from lightest to heaviest.
    struct Variable {
        var url: URL
        var weights: [FontStyleOption]
        var lightest: FontStyleOption { weights.first! }
        /// The heaviest instance at or under Bold (700), the weight the user wants for headings.
        var bold: FontStyleOption { weights.last { ($0.weight ?? 0) <= 700 }! }
        var `default`: FontStyleOption { FontFile.styles(at: url).first(where: \.isDefault)! }
    }

    static let variable: Variable? = {
        for url in variableCandidates where FileManager.default.fileExists(atPath: url.path) {
            let plain = FontFile.styles(at: url)
                .filter { $0.weight != nil && Set($0.style.variations.keys).isSubset(of: ["wght"]) }
                .sorted { $0.weight! < $1.weight! }
            if plain.count >= 4, let heaviest = plain.last, (heaviest.weight ?? 0) >= 700 {
                return Variable(url: url, weights: plain)
            }
        }
        return nil
    }()
}

/// A page of a PDF as pixels, and how dark part of it is.
struct Picture {
    let image: CGImage

    init?(page1 pdf: Data, scale: CGFloat = 2, name: String? = nil) {
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
        self.image = image
        // Like the UI tests' snapshots, a PNG goes to QP_SNAPSHOTS for people to look at.
        if let name, let folder = ProcessInfo.processInfo.environment["QP_SNAPSHOTS"],
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try? png.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
            try? pdf.write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".pdf"))
        }
    }

    /// How much ink (darkness, summed over the pixels) is in the part of the page from `x` points in
    /// from the left, and from the top down to `top` points; the scale is the one the picture was drawn at.
    func ink(fromX x: CGFloat = 0, toTop top: CGFloat, scale: CGFloat = 2) -> Double {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        var total = 0.0
        // The first row in memory is the top of the picture.
        for row in 0..<min(Int(top * scale), height) {
            for column in Int(x * scale)..<width {
                let i = (row * width + column) * 4
                total += 255 - (Double(bytes[i]) + Double(bytes[i + 1]) + Double(bytes[i + 2])) / 3
            }
        }
        return total
    }
}

@Suite struct VariableFontTests {
    let quote = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)

    /// The title ("Quote") sits top right; nothing else on the page is in this corner.
    func titleInk(_ pdf: Data, name: String? = nil) throws -> Double {
        let picture = try #require(Picture(page1: pdf, name: name))
        return picture.ink(fromX: 400, toTop: 100)
    }

    // MARK: The styles a font file offers

    @Test(.enabled(if: SystemFonts.variable != nil))
    func aVariableFontListsEachNamedInstanceWithItsWeight() throws {
        let font = try #require(SystemFonts.variable)
        let styles = FontFile.styles(at: font.url)
        #expect(styles.count >= 4)
        for style in styles {
            let weight = try #require(style.weight, "\(style.name) has a weight")
            #expect(style.label == "\(style.name) (\(weight))")
        }
        // The weight comes from the instance's wght value: the Bold instance says 700 or so.
        #expect(font.bold.label.hasSuffix("(\(font.bold.weight!))"))
        #expect(font.bold.weight! >= 600 && font.bold.weight! <= 700)
        #expect(font.lightest.weight! < font.bold.weight!)
        // One style is the font's own default, and the weights climb from there.
        #expect(styles.filter(\.isDefault).count == 1)
        // Every style has a name of its own, so a saved style finds its instance again.
        #expect(Set(styles.map(\.id)).count == styles.count)
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: SystemFonts.georgia.path)))
    func aStaticFontWithOneFaceListsItsOneStyle() {
        let styles = FontFile.styles(at: SystemFonts.georgia)
        #expect(styles.count == 1)
        #expect(styles.first?.label == "Regular")
        #expect(styles.first?.weight == nil)
        #expect(styles.first?.isDefault == true)
    }

    @Test func aFileThatIsNotAFontListsNothing() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("notes-\(UUID().uuidString).ttf")
        try Data("not a font".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(FontFile.styles(at: url).isEmpty)
        #expect(FontFile.font(at: url, style: nil, size: 12) == nil)
    }

    // MARK: Making the font from a style

    @Test(.enabled(if: SystemFonts.variable != nil))
    func aStyleMakesTheFontOfThatInstance() throws {
        let font = try #require(SystemFonts.variable)
        let bold = try #require(FontFile.font(at: font.url, style: font.bold.style, size: 26))
        #expect(CTFontCopyPostScriptName(bold) as String == font.bold.style.postScriptName)
        let thin = try #require(FontFile.font(at: font.url, style: font.lightest.style, size: 26))
        #expect(CTFontCopyPostScriptName(thin) as String == font.lightest.style.postScriptName)
        // The label's weight is the axis value to the nearest whole number.
        #expect(abs(axisValue("wght", of: bold)! - Double(font.bold.weight!)) <= 0.5)
        #expect(abs(axisValue("wght", of: thin)! - Double(font.lightest.weight!)) <= 0.5)
    }

    /// With no style chosen a variable font draws as its default style, not as the first one in the
    /// file (which is usually the thinnest).
    @Test(.enabled(if: SystemFonts.variable != nil))
    func noStyleIsTheFontsOwnDefaultInstance() throws {
        let font = try #require(SystemFonts.variable)
        let made = try #require(FontFile.font(at: font.url, style: nil, size: 26))
        #expect(CTFontCopyPostScriptName(made) as String == font.default.style.postScriptName)
        #expect(font.default.id != FontFile.styles(at: font.url).first?.id)
    }

    /// A style the file doesn't have by name is rebuilt from its axis values on the default; with
    /// neither it is the default.
    @Test(.enabled(if: SystemFonts.variable != nil))
    func aStyleTheFileHasNoNameForIsRebuiltFromItsAxisValues() throws {
        let font = try #require(SystemFonts.variable)
        let renamed = FontStyle(postScriptName: "Gone-Bold", variations: ["wght": 700])
        let rebuilt = try #require(FontFile.font(at: font.url, style: renamed, size: 26))
        #expect(axisValue("wght", of: rebuilt) == 700)
        let lost = try #require(FontFile.font(at: font.url, style: FontStyle(postScriptName: "Gone-Bold"), size: 26))
        #expect(CTFontCopyPostScriptName(lost) as String == font.default.style.postScriptName)
    }

    /// Whether the PDF names this instance as an embedded font. A font with named instances is
    /// embedded under the instance's own name ("ArchivoItalic-Bold"); one without is named after its
    /// base face with the axis values spelled out in 16.16 hex ("…_wght2BC0000" is weight 700).
    private func embeds(_ option: FontStyleOption, in pdf: Data) -> Bool {
        let bytes = String(decoding: pdf, as: UTF8.self)
        if bytes.contains(option.style.postScriptName.trimmingCharacters(in: CharacterSet(charactersIn: "."))) { return true }
        guard let weight = option.style.variations["wght"] else { return false }
        return bytes.contains("wght" + String(Int(weight * 65536), radix: 16, uppercase: true))
    }

    private func axisValue(_ tag: String, of font: CTFont) -> Double? {
        let variation = CTFontCopyVariation(font) as? [NSNumber: NSNumber]
        let id = tag.utf8.reduce(0) { ($0 << 8) | Int($1) }
        return variation?[NSNumber(value: id)]?.doubleValue
    }

    // MARK: A quote PDF with a variable heading font

    /// The risky part: a PDF drawn with one instance of a variable font. It opens in PDFKit, its text
    /// extracts, it holds that instance, and the heading really is heavier.
    @Test(.enabled(if: SystemFonts.variable != nil))
    func aQuoteWithAVariableHeadingFontAtBoldRendersBold() throws {
        let font = try #require(SystemFonts.variable)
        let boldData = DocumentRenderer.render(
            quote, style: PDFStyle(headingFontURL: font.url, headingFontStyle: font.bold.style))

        // It opens in PDFKit, and the text comes out.
        let document = try #require(PDFDocument(data: boldData))
        #expect(document.pageCount >= 1)
        let text = Sample.text(document)
        #expect(text.contains("Quote"))
        #expect(text.contains("Q-0001"))
        #expect(text.contains("Booking app, phase 1"))

        // The PDF holds the Bold instance of the file, not the default one.
        #expect(embeds(font.bold, in: boldData))

        // And it is bold: more ink in the title than the lightest instance, and than the default.
        let thinData = DocumentRenderer.render(
            quote, style: PDFStyle(headingFontURL: font.url, headingFontStyle: font.lightest.style))
        let defaultData = DocumentRenderer.render(quote, style: PDFStyle(headingFontURL: font.url))
        let bold = try titleInk(boldData, name: "variable-heading-bold")
        let thin = try titleInk(thinData, name: "variable-heading-lightest")
        let normal = try titleInk(defaultData, name: "variable-heading-default")
        #expect(bold > thin * 1.5)
        if font.bold.weight! > (font.default.weight ?? 0) { #expect(bold > normal) }
        if font.lightest.id != font.default.id { #expect(normal > thin) }
    }

    /// The chosen style reaches the PDF by way of the brand, the way the app builds a document's style.
    @Test(.enabled(if: SystemFonts.variable != nil))
    func theBrandsHeadingStyleIsUsedWhenThePDFStyleIsBuiltFromIt() throws {
        let font = try #require(SystemFonts.variable)
        let assets = FileManager.default.temporaryDirectory.appendingPathComponent("assets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: assets) }
        // A link, not a copy: system variable fonts are big and the disk is not.
        try FileManager.default.createSymbolicLink(at: assets.appendingPathComponent("heading-font-TEST.ttf"),
                                                   withDestinationURL: font.url)

        var brand = Sample.brand
        brand.headingFontFile = "heading-font-TEST.ttf"
        brand.headingFontStyle = font.bold.style
        let style = PDFStyle(brand: brand, assetsFolder: assets)
        #expect(style.headingFontStyle == font.bold.style)
        let chosen = CTFontCopyPostScriptName(style.heading(26)) as String
        #expect(chosen == font.bold.style.postScriptName)

        brand.headingFontStyle = nil
        let plain = PDFStyle(brand: brand, assetsFolder: assets)
        #expect(CTFontCopyPostScriptName(plain.heading(26)) as String == font.default.style.postScriptName)
    }
}
