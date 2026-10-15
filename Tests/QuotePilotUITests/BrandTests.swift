import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct BrandTests {
    @Test func editingTheBrandSavesIt() throws {
        let model = try UIFixture.sampleModel()
        model.brandBinding.wrappedValue.businessName = "Sample Studio Two"
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.businessName == "Sample Studio Two")
    }

    /// Day counts past a year would put a due date where `Day` can't go, and the library would no
    /// longer open; whatever reaches the model is kept within 0 to 365.
    @Test func dayCountsAreKeptWithinAYear() throws {
        let model = try UIFixture.sampleModel()
        var brand = model.library.brand
        brand.paymentDueDays = 9_999
        brand.quoteValidDays = -3
        model.updateBrand(brand)
        #expect(model.library.brand.paymentDueDays == 365)
        #expect(model.library.brand.quoteValidDays == 0)
        #expect(model.message == nil)
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.paymentDueDays == 365)
        #expect(saved.brand.quoteValidDays == 0)
    }

    // MARK: One file picker for the whole app

    /// A font file that ships with macOS, or nil when this Mac has none of the usual ones.
    private func systemFont() -> URL? {
        ["/System/Library/Fonts/Supplemental/Arial.ttf", "/System/Library/Fonts/Supplemental/Courier New.ttf",
         "/System/Library/Fonts/Supplemental/Georgia.ttf", "/System/Library/Fonts/Supplemental/Verdana.ttf"]
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    @Test func theBrandPickersUseTheOneImporterWithTheirOwnFileTypes() {
        #expect(FileChoice.logo.contentTypes == [.png, .jpeg, .pdf])
        #expect(FileChoice.headingFont.contentTypes == [.font])
        #expect(FileChoice.returnedQuote.contentTypes == [.pdf])
        #expect(FileChoice.legacyBackup.contentTypes == [.json])
    }

    /// The logo choice reaches the logo handler, and never the returned-quote reader: a PDF logo
    /// would otherwise be read as a client's reply.
    @Test func aChosenLogoReachesTheLogoHandlerAndNotTheReplyReader() throws {
        let model = try UIFixture.sampleModel()
        let quotes = model.library.quotes.count
        model.choosingFile = .logo
        // SwiftUI may close the panel (clearing the choice) before it reports the file.
        model.choosingFile = nil
        model.fileChosen(.success(try UIFixture.file("my logo.png", UIFixture.pngData())))
        let png = try #require(model.library.brand.logoFile)
        #expect(png.hasPrefix("logo-") && png.hasSuffix(".png"))
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        #expect(model.openQuoteID == nil)
        #expect(model.choosingFile == nil)

        // A PDF logo is a fine logo; it is not a returned quote.
        model.choosingFile = .logo
        model.fileChosen(.success(try UIFixture.file("my logo.pdf", model.pdf(model.sampleContent()))))
        let pdf = try #require(model.library.brand.logoFile)
        #expect(pdf != png && pdf.hasSuffix(".pdf"))
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        #expect(model.openQuoteID == nil)
        #expect(model.library.quotes.count == quotes)
    }

    @Test func aChosenHeadingFontReachesTheFontHandler() throws {
        let font = try #require(systemFont(), "No system font to try")
        let model = try UIFixture.sampleModel()
        model.choosingFile = .headingFont
        model.choosingFile = nil
        model.fileChosen(.success(font))
        let name = try #require(model.library.brand.headingFontFile)
        #expect(name.hasPrefix("heading-font-") && name.hasSuffix(".ttf"))
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        #expect(model.openQuoteID == nil)
        #expect(model.library.brand.logoFile == nil)
    }

    /// A pick can't be taken for an earlier one: the choice is forgotten once it is answered, a
    /// cancelled panel included.
    @Test func aBrandPickIsNeverTakenForAnEarlierChoice() throws {
        let model = try UIFixture.sampleModel()
        model.choosingFile = .returnedQuote
        model.fileChosen(.failure(CocoaError(.userCancelled)))
        #expect(model.message == nil)
        // Nothing is being chosen now, so a stray report does nothing at all.
        model.fileChosen(.success(try UIFixture.file("my logo.png", UIFixture.pngData())))
        #expect(model.library.brand.logoFile == nil)
        #expect(model.message == nil)
        #expect(model.dialog == nil)
    }

    @Test func aFileTheBrandCantUseSaysSoOnce() throws {
        let model = try UIFixture.sampleModel()
        model.choosingFile = .logo
        model.fileChosen(.success(try UIFixture.file("notes.png", Data("not a picture".utf8))))
        #expect(model.message?.title == "Not an Image")
        #expect(model.library.brand.logoFile == nil)
        model.message = nil
        model.choosingFile = .headingFont
        model.fileChosen(.success(try UIFixture.file("notes.ttf", Data("not a font".utf8))))
        #expect(model.message?.title == "Not a Font")
        #expect(model.library.brand.headingFontFile == nil)
    }

    @Test func theBusinessTabDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .brand
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "brand")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theLookTabDraws() throws {
        let model = try UIFixture.sampleModel()
        let rep = Snapshot.render(BrandView(model: model, tab: .look).background(Win95.face),
                                  size: CGSize(width: 1000, height: 640), name: "brand-look")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
