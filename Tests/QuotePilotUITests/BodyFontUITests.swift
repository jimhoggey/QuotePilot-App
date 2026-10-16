import AppKit
import Foundation
import PDFKit
import SwiftUI
import Testing
import QuotePilotCore
import QuotePilotPDF
@testable import QuotePilotUI

/// Brand > Look > Body font: the font for the text of quotes and invoices.
@MainActor
@Suite struct BodyFontUITests {
    static let georgia = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Georgia.ttf")
    static let haveGeorgia = FileManager.default.fileExists(atPath: georgia.path)

    // MARK: The one file picker

    @Test(.enabled(if: BodyFontUITests.haveGeorgia))
    func aChosenBodyFontReachesTheBodyFontHandler() throws {
        let model = try UIFixture.sampleModel()
        model.choosingFile = .bodyFont
        model.choosingFile = nil
        // SwiftUI may close the panel (clearing the choice) before it reports the file.
        model.fileChosen(.success(Self.georgia))
        let name = try #require(model.library.brand.bodyFontFile)
        #expect(name.hasPrefix("body-font-") && name.hasSuffix(".ttf"))
        #expect(model.library.brand.headingFontFile == nil)
        #expect(model.library.brand.logoFile == nil)
        #expect(model.library.brand.bodyFontStyle == nil)
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        #expect(model.openQuoteID == nil)
        #expect(model.bodyFontName == "Georgia")
        #expect(model.headingFontName == nil)
        // The panel takes font files, and is the one open panel there is: the model's choice is
        // forgotten once answered, so a stray report afterwards does nothing.
        #expect(model.choosingFile == nil)
        let before = model.library.brand
        model.fileChosen(.success(Self.georgia))
        #expect(model.library.brand == before)
    }

    /// A body pick and a heading pick each reach their own font, and neither touches the other's.
    @Test(.enabled(if: BodyFontUITests.haveGeorgia))
    func theHeadingFontAndTheBodyFontAreChosenSeparately() throws {
        let model = try UIFixture.sampleModel()
        model.choosingFile = .headingFont
        model.fileChosen(.success(Self.georgia))
        let heading = try #require(model.library.brand.headingFontFile)
        #expect(model.library.brand.bodyFontFile == nil)

        model.choosingFile = .bodyFont
        model.fileChosen(.success(Self.georgia))
        let body = try #require(model.library.brand.bodyFontFile)
        #expect(model.library.brand.headingFontFile == heading)
        #expect(body != heading && body.hasPrefix("body-font-") && heading.hasPrefix("heading-font-"))

        model.removeBodyFont()
        #expect(model.library.brand.bodyFontFile == nil)
        #expect(model.library.brand.headingFontFile == heading)
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.headingFontFile == heading)
        #expect(saved.brand.bodyFontFile == nil)
    }

    @Test func aFileThatIsNotAFontIsNotABodyFont() throws {
        let model = try UIFixture.sampleModel()
        model.choosingFile = .bodyFont
        model.fileChosen(.success(try UIFixture.file("notes.ttf", Data("not a font".utf8))))
        #expect(model.message?.title == "Not a Font")
        #expect(model.message?.text.contains("notes.ttf") == true)
        #expect(model.library.brand.bodyFontFile == nil)
        #expect(model.library.brand.headingFontFile == nil)
        #expect(model.dialog == nil)
    }

    // MARK: Its style

    @Test(.enabled(if: VariableFixture.available && BodyFontUITests.haveGeorgia))
    func aBodyStyleIsSavedWithTheBrandAndForgottenWithTheFont() throws {
        let font = try #require(VariableFixture.variable)
        let model = try UIFixture.sampleModel()
        model.importBodyFont(from: font.url)
        // A body font starts on its Regular, not on the font's default (which can be heavy).
        #expect(model.library.brand.bodyFontStyle == FontFile.startingStyle(at: font.url, nearWeight: 400))
        #expect(model.library.brand.bodyFontStyle != nil)
        let options = FontStylePicker.options(for: model.bodyFontURL)
        #expect(options.count > 1)

        let light = try #require(font.weights.first { ($0.weight ?? 0) >= 300 })
        model.brandBinding.wrappedValue.bodyFontStyle = light.style
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.bodyFontStyle == light.style)
        #expect(saved.brand.headingFontStyle == nil)

        // A new body font starts on its own default; so does none.
        model.importBodyFont(from: Self.georgia)
        #expect(model.library.brand.bodyFontStyle == nil)
        model.importBodyFont(from: font.url)
        model.brandBinding.wrappedValue.bodyFontStyle = light.style
        model.removeBodyFont()
        #expect(model.library.brand.bodyFontFile == nil)
        #expect(model.library.brand.bodyFontStyle == nil)
    }

    // MARK: In the PDF

    /// The sample quote beside the Brand tabs is the real renderer's output, so it shows the body
    /// font at once; the text still reads, and a PNG of page 1 can be looked at (QP_SNAPSHOTS).
    @Test(.enabled(if: BodyFontUITests.haveGeorgia))
    func aQuoteUsesTheBodyFontForItsText() throws {
        let model = try UIFixture.sampleModel()
        model.importBodyFont(from: Self.georgia)
        let pdf = model.pdf(model.sampleContent())
        let document = try #require(PDFDocument(data: pdf))
        let text = document.page(at: 0)?.string ?? ""
        #expect(text.contains("Planning meeting"))
        #expect(text.contains("Sample Client Pty Ltd"))
        #expect(text.contains("Prices are fixed for the work listed."))
        #expect(String(decoding: pdf, as: UTF8.self).contains("Georgia"))
        // PDFKit says the lines are drawn in it, and the headings (no heading font chosen) are not.
        let planning = try #require(document.findString("Planning meeting", withOptions: .literal).first?.attributedString)
        #expect((planning.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName == "Georgia")
        let title = try #require(document.findString("Quote", withOptions: .literal).first?.attributedString)
        #expect((title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontName != "Georgia")
        _ = Snapshot.renderPage(pdf, name: "quote-page-body-font")
    }

    /// With no body font, a quote is drawn exactly as it was before there was one.
    @Test func withNoBodyFontTheQuoteIsUnchanged() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.library.brand.bodyFontFile == nil)
        let content = model.sampleContent()
        let now = model.pdf(content)
        let before = DocumentRenderer.render(content, style: PDFStyle(accentHex: model.library.brand.accentHex))
        let a = try #require(Snapshot.renderPage(now, name: "quote-page-no-body-font"))
        let b = try #require(Snapshot.renderPage(before, name: "quote-page-no-body-font-before"))
        #expect(a.tiffRepresentation == b.tiffRepresentation)
        #expect(String(decoding: now, as: UTF8.self).contains("Georgia") == false)
        let fonts = Set(PDFDocument(data: now)?.page(at: 0)?.attributedString?.fontNames ?? [])
        #expect(!fonts.isEmpty)
        #expect(!fonts.contains("Georgia"))
    }

    // MARK: On the Look tab

    @Test func theLookTabSaysWhatEachFontIsFor() {
        #expect(LookTab.headingFontHint == "A TTF or OTF file, used for document titles and headings. For a variable font, choose its style.")
        #expect(LookTab.bodyFontHint == "A TTF or OTF file for the text of quotes and invoices. Leave it empty to use the standard Mac font.")
    }

    @Test(.enabled(if: BodyFontUITests.haveGeorgia))
    func theLookTabDrawsWithABodyFont() throws {
        let model = try UIFixture.sampleModel()
        model.importBodyFont(from: Self.georgia)
        let rep = Snapshot.render(BrandView(model: model, tab: .look).background(Win95.face),
                                  size: CGSize(width: 980, height: 620), name: "brand-look-body-font")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}

private extension NSAttributedString {
    /// The names of the fonts the text is drawn in.
    var fontNames: [String] {
        var names: [String] = []
        enumerateAttribute(.font, in: NSRange(location: 0, length: length)) { value, _, _ in
            if let font = value as? NSFont { names.append(font.fontName) }
        }
        return names
    }
}
