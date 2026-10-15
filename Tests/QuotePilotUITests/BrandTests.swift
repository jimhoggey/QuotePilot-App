import AppKit
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

    // MARK: The hourly rate

    @Test func theHourlyRateSavesThroughTheModel() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.library.brand.hourlyRate == nil)
        model.brandBinding.wrappedValue.hourlyRate = Money(dollars: 95, cents: 50)
        #expect(model.message == nil)
        #expect(model.library.brand.hourlyRate == Money(dollars: 95, cents: 50))
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.hourlyRate == Money(dollars: 95, cents: 50))

        // Clearing the field puts it back to none.
        model.brandBinding.wrappedValue.hourlyRate = nil
        guard case .loaded(let cleared) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(cleared.brand.hourlyRate == nil)
    }

    /// The field takes $0 up to $10,000,000, and whatever else reaches the model is kept inside that:
    /// outside it the library would no longer open.
    @Test func anHourlyRateIsKeptWithinZeroToTenMillion() throws {
        let model = try UIFixture.sampleModel()
        var brand = model.library.brand
        brand.hourlyRate = Money(dollars: 20_000_000)
        model.updateBrand(brand)
        #expect(model.library.brand.hourlyRate == Money(dollars: 10_000_000))
        brand.hourlyRate = Money(dollars: -5)
        model.updateBrand(brand)
        #expect(model.library.brand.hourlyRate == .zero)
        #expect(model.message == nil)
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.hourlyRate == .zero)
    }

    @Test func theHourlyRateFieldTakesAmountsAndRefusesTheRest() {
        func leave(_ text: String, stored: Money) -> (beep: Bool, text: String) {
            CommitField<Money>.onLeave(text: text, stored: stored,
                                       format: { HourlyRateField.text($0, currencyCode: "AUD") },
                                       parse: FieldParser.hourlyRate)
        }
        // "abc" is refused with a beep, and the stored rate is put back.
        let refused = leave("abc", stored: Money(dollars: 95))
        #expect(refused.beep)
        #expect(refused.text == "$95.00")
        #expect(leave("-5", stored: Money(dollars: 95)).beep)
        #expect(leave("12abc", stored: .zero).beep)
        #expect(leave("abc", stored: .zero).text == "")
        // An amount is tidied; blank is no rate and no beep.
        #expect(leave("95", stored: Money(dollars: 95)) == (beep: false, text: "$95.00"))
        #expect(leave("", stored: .zero) == (beep: false, text: ""))
        // Typed text is committed as it goes: an amount, or blank for none.
        #expect(CommitField<Money>.liveCommit(text: "110", stored: Money(dollars: 95), parse: FieldParser.hourlyRate)
                == Money(dollars: 110))
        #expect(CommitField<Money>.liveCommit(text: "", stored: Money(dollars: 95), parse: FieldParser.hourlyRate) == .zero)
        #expect(CommitField<Money>.liveCommit(text: "abc", stored: Money(dollars: 95), parse: FieldParser.hourlyRate) == nil)
        #expect(CommitField<Money>.liveCommit(text: "$", stored: Money(dollars: 95), parse: FieldParser.hourlyRate) == nil)
        // No rate shows as an empty field, and a $0 typed there means none.
        #expect(HourlyRateField.text(.zero, currencyCode: "AUD") == "")
        #expect(HourlyRateField.stored(.zero) == nil)
        #expect(HourlyRateField.stored(Money(dollars: 95)) == Money(dollars: 95))
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

    /// The Look tab, drawn at the smallest window (980 x 620), with its Hourly rate group right under
    /// the Logo (snapshot: brand-look-small).
    @Test func theLookTabDrawsInTheSmallestWindow() throws {
        let model = try UIFixture.sampleModel()
        var brand = model.library.brand
        brand.hourlyRate = Money(dollars: 95)
        model.updateBrand(brand)
        model.section = .brand
        let rep = Snapshot.render(BrandView(model: model, tab: .look).background(Win95.face),
                                  size: CGSize(width: 778, height: 492), name: "brand-look-small")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// The smallest window (980 x 620) gives the section 492 points (see the Dashboard's fit test),
    /// and the Look tab's groups sit in what is left of that after the Brand screen's padding (16),
    /// the tab strip (24) and the panel's padding (20): 432. The groups must fit it whole, at the
    /// narrowest the tab column goes (460 less the panel's padding and the scroller's gap).
    @Test func theLookTabFitsTheSmallestWindow() throws {
        let model = try UIFixture.sampleModel()
        _ = NSApplication.shared
        let look = LookTab(model: model, brand: model.brandBinding).groupBoxStyle(.win95)
        let needed = NSHostingView(rootView: look.frame(width: 460 - 20 - 6)).fittingSize
        let available: CGFloat = 620 - 28 - 66 - 26 - 8 - 16 - 24 - 20
        #expect(needed.height <= available, "the Look tab needs \(needed.height) of \(available)")
    }
}
