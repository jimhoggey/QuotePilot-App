import AppKit
import CoreText
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

/// The brand's body font draws the text of a document; headings keep the heading font.
@Suite struct BodyFontTests {
    static let supplemental = "/System/Library/Fonts/Supplemental/"
    static let georgia = URL(fileURLWithPath: supplemental + "Georgia.ttf")
    static let courier = URL(fileURLWithPath: supplemental + "Courier New.ttf")
    static let helvetica = URL(fileURLWithPath: "/System/Library/Fonts/Helvetica.ttc")
    static let haveGeorgiaAndCourier = FileManager.default.fileExists(atPath: georgia.path)
        && FileManager.default.fileExists(atPath: courier.path)

    let quote = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)

    /// The fonts the PDF draws with, by the PostScript names it embeds them under ("AAAAAB+Georgia").
    func embeddedFonts(_ pdf: Data) -> Set<String> {
        let bytes = String(decoding: pdf, as: UTF8.self)
        var names = Set<String>()
        var rest = bytes[...]
        while let range = rest.range(of: "/BaseFont /") {
            rest = rest[range.upperBound...]
            let name = rest.prefix { !$0.isWhitespace && $0 != "/" && $0 != ">" }
            names.insert(String(name.drop { $0 != "+" }.dropFirst()))
        }
        return names
    }

    /// The font each piece of text on page 1 is drawn in, from PDFKit's reading of the page.
    func fontNames(in pdf: Data, forText snippets: [String]) throws -> [String: String] {
        let document = try #require(PDFDocument(data: pdf))
        let page = try #require(document.page(at: 0))
        var found: [String: String] = [:]
        for snippet in snippets {
            let selection = try #require(document.findString(snippet, withOptions: .literal).first { $0.pages.first === page },
                                         "\(snippet) is on page 1")
            let text = try #require(selection.attributedString)
            let font = try #require(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, "\(snippet) has a font")
            found[snippet] = font.fontName
        }
        return found
    }

    // MARK: Where the body font is used

    @Test(.enabled(if: BodyFontTests.haveGeorgiaAndCourier))
    func theBodyFontDrawsTheTextAndTheHeadingFontTheHeadings() throws {
        let data = DocumentRenderer.render(quote, style: PDFStyle(headingFontURL: Self.courier, bodyFontURL: Self.georgia))

        // It opens in PDFKit and the text comes out.
        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount >= 1)
        let text = Sample.text(document)
        #expect(text.contains("Sample Studio"))
        #expect(text.contains("Walkthrough of the current process"))
        #expect(text.contains("Prices are fixed for the work listed."))

        // Both fonts are in the PDF, and each piece of text is in the one it should be.
        let fonts = embeddedFonts(data)
        #expect(fonts.contains("Georgia"))
        #expect(fonts.contains { $0.hasPrefix("CourierNewPS") })
        let used = try fontNames(in: data, forText: [
            "Quote", "$1,500.00",                                   // headings: the title and the amount
            "Sample Studio", "hello@example.com",                   // the sender, its details
            "Sample Client Pty Ltd", "1 Example St",                // the client
            "Discovery", "Walkthrough of the current process",      // a line, its detail
            "Prices are fixed for the work listed.",                // the terms
        ])
        #expect(used["Quote"]?.hasPrefix("CourierNewPS") == true)
        #expect(used["$1,500.00"]?.hasPrefix("CourierNewPS") == true)
        for snippet in used.keys where snippet != "Quote" && snippet != "$1,500.00" {
            #expect(used[snippet] == "Georgia", "\(snippet) is in \(used[snippet] ?? "no font")")
        }
        // Nothing on the page is left in the standard Mac font.
        #expect(!fonts.contains { $0.contains("SFNS") || $0.contains("SFUI") || $0.contains("Helvetica") })

        _ = Picture(page1: data, name: "body-font-georgia-courier-headings")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: BodyFontTests.georgia.path)))
    func aBodyFontWithNoHeadingFontLeavesTheHeadingsInTheStandardFont() throws {
        let data = DocumentRenderer.render(quote, style: PDFStyle(bodyFontURL: Self.georgia))
        let used = try fontNames(in: data, forText: ["Quote", "Discovery"])
        #expect(used["Discovery"] == "Georgia")
        #expect(used["Quote"] != "Georgia")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: BodyFontTests.georgia.path)))
    func theBodyFontReachesThePDFByWayOfTheBrand() throws {
        let assets = FileManager.default.temporaryDirectory.appendingPathComponent("assets-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: assets) }
        try FileManager.default.copyItem(at: Self.georgia, to: assets.appendingPathComponent("body-font-TEST.ttf"))

        var brand = Sample.brand
        brand.bodyFontFile = "body-font-TEST.ttf"
        let style = PDFStyle(brand: brand, assetsFolder: assets)
        #expect(style.bodyFontURL == assets.appendingPathComponent("body-font-TEST.ttf"))
        #expect(style.headingFontURL == nil)
        let data = DocumentRenderer.render(.quote(Sample.quote(), client: Sample.client, brand: brand), style: style)
        #expect(embeddedFonts(data).contains("Georgia"))
    }

    // MARK: With no body font, nothing changes

    /// The standard Mac font is asked for as it always was, at every weight the document uses.
    @Test func withNoBodyFontTheTextFontIsTheStandardMacFontAsBefore() {
        let style = PDFStyle()
        #expect(style.bodyFontURL == nil)
        for weight in [NSFont.Weight.regular, .medium, .semibold] {
            for size in [7.5, 8.5, 9.5, 10.5, 13] as [CGFloat] {
                let expected = NSFont.systemFont(ofSize: size, weight: weight) as CTFont
                #expect(CFEqual(style.body(size, weight: weight), expected), "\(size) at \(weight.rawValue)")
            }
        }
        // A brand with no body font builds the same style.
        let fromBrand = PDFStyle(brand: Sample.brand, assetsFolder: nil)
        #expect(fromBrand.bodyFontURL == nil && fromBrand.bodyFontStyle == nil)
    }

    @Test func aBodyFontThatWontLoadFallsBackToTheStandardFontAndTheSamePDF() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gone-\(UUID().uuidString).ttf")
        let plain = DocumentRenderer.render(quote, style: PDFStyle())
        let missing = DocumentRenderer.render(quote, style: PDFStyle(bodyFontURL: url))
        #expect(embeddedFonts(missing) == embeddedFonts(plain))
        #expect(Sample.text(try #require(PDFDocument(data: missing))) == Sample.text(try #require(PDFDocument(data: plain))))
        // Page 1 is the same picture.
        let a = try #require(Picture(page1: plain))
        let b = try #require(Picture(page1: missing))
        #expect(a.ink(toTop: 842) == b.ink(toTop: 842))
    }

    // MARK: Emphasis within the body font

    /// Body text asks for medium and semibold in places. The font gives the file's own heavier face of
    /// the same slant, and never a fake bold.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: BodyFontTests.helvetica.path)))
    func emphasisIsTheFilesOwnHeavierFaceOfTheSameSlant() throws {
        func name(_ style: String?, weight: CGFloat) throws -> String {
            let font = try #require(FontFile.font(at: Self.helvetica, style: style.map { FontStyle(postScriptName: $0) },
                                                  size: 10, weight: weight))
            return CTFontCopyPostScriptName(font) as String
        }
        #expect(try name(nil, weight: 0) == "Helvetica")
        #expect(try name(nil, weight: 0.3) == "Helvetica-Bold")
        #expect(try name("Helvetica-Oblique", weight: 0.3) == "Helvetica-BoldOblique")
        // Nothing is heavier than Bold in the file, so Bold stays Bold.
        #expect(try name("Helvetica-Bold", weight: 0.3) == "Helvetica-Bold")
        // Light asks for a little more and gets Regular, the nearest face that is heavier.
        #expect(try name("Helvetica-Light", weight: 0.3) == "Helvetica")
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: BodyFontTests.georgia.path)))
    func aFontWithOneFaceKeepsItForEmphasisRatherThanFakingABold() throws {
        for weight in [0, 0.23, 0.3] as [CGFloat] {
            let font = try #require(FontFile.font(at: Self.georgia, style: nil, size: 10, weight: weight))
            #expect(CTFontCopyPostScriptName(font) as String == "Georgia")
            #expect(CTFontGetSymbolicTraits(font).contains(.traitBold) == false)
        }
    }

    @Test(.enabled(if: SystemFonts.variable != nil))
    func emphasisInAVariableFontStaysOnTheSameWidthAndMovesUpTheWeightAxis() throws {
        let font = try #require(SystemFonts.variable)
        let regular = try #require(font.weights.first { ($0.weight ?? 0) >= 400 })
        func weight(of made: CTFont) -> Double {
            let variation = CTFontCopyVariation(made) as? [NSNumber: NSNumber]
            let id = "wght".utf8.reduce(0) { ($0 << 8) | Int($1) }
            return variation?[NSNumber(value: id)]?.doubleValue ?? 0
        }
        let plain = try #require(FontFile.font(at: font.url, style: regular.style, size: 10))
        let semibold = try #require(FontFile.font(at: font.url, style: regular.style, size: 10, weight: 0.3))
        #expect(weight(of: semibold) > weight(of: plain))
        #expect(weight(of: semibold) <= 700)
        // Just a little more asks for a little more, not the same.
        let medium = try #require(FontFile.font(at: font.url, style: regular.style, size: 10, weight: 0.23))
        #expect(weight(of: medium) > weight(of: plain))
        #expect(weight(of: medium) <= weight(of: semibold))
    }

    /// A variable body font chosen at one style is drawn in it, and a quote with it still renders and reads.
    @Test(.enabled(if: SystemFonts.variable != nil))
    func aVariableBodyFontAtTheChosenStyleRenders() throws {
        let font = try #require(SystemFonts.variable)
        let light = try #require(font.weights.first { ($0.weight ?? 0) >= 300 })
        let data = DocumentRenderer.render(quote, style: PDFStyle(bodyFontURL: font.url, bodyFontStyle: light.style))
        let document = try #require(PDFDocument(data: data))
        let text = Sample.text(document)
        #expect(text.contains("Discovery") && text.contains("Q-0001"))
        // Lighter body text carries less ink than the heavier default on the same page.
        let heavier = DocumentRenderer.render(
            quote, style: PDFStyle(bodyFontURL: font.url, bodyFontStyle: font.bold.style))
        let lightPicture = try #require(Picture(page1: data, name: "variable-body-light"))
        let heavyPicture = try #require(Picture(page1: heavier, name: "variable-body-bold"))
        #expect(lightPicture.ink(toTop: 842) < heavyPicture.ink(toTop: 842))
    }
}
