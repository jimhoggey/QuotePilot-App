import AppKit
import Foundation
import PDFKit
import SwiftUI
import Testing
import UniformTypeIdentifiers
import QuotePilotCore
import QuotePilotPDF
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

    // MARK: When the sample quote redraws

    /// Typing saves as it goes but leaves the sample quote alone; ending the edit brings it up to date.
    @Test func typingWaitsForTheEditToEndBeforeTheSampleRedraws() throws {
        let model = try UIFixture.sampleModel()
        let before = model.library.brand
        let sample = model.sampleContent()
        let typing = model.brandTypingBinding
        typing.wrappedValue.businessName = "Sample Studio T"
        typing.wrappedValue.businessName = "Sample Studio Two"
        typing.wrappedValue.hourlyRate = Money(dollars: 9)
        typing.wrappedValue.hourlyRate = Money(dollars: 95)
        // Saved at once...
        #expect(model.library.brand.businessName == "Sample Studio Two")
        #expect(model.library.brand.hourlyRate == Money(dollars: 95))
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.brand.businessName == "Sample Studio Two")
        // ...but the sample is drawn as it was.
        #expect(model.previewBrand == before)
        #expect(model.sampleContent() == sample)

        model.brandEditEnded()
        #expect(model.previewBrand == model.library.brand)
        #expect(model.previewBrand.businessName == "Sample Studio Two")
        #expect(model.sampleContent() != sample)

        // The next edit holds it again, at what it now shows.
        typing.wrappedValue.abn = "12 345 678 901"
        #expect(model.previewBrand.businessName == "Sample Studio Two")
        #expect(model.previewBrand.abn == before.abn)
        model.brandEditEnded()
        #expect(model.previewBrand.abn == "12 345 678 901")
    }

    /// A checkbox, a colour swatch or a logo changes in one action, so the sample redraws at once,
    /// with whatever was typed before it.
    @Test func aCheckboxColourOrLogoRedrawsTheSampleAtOnce() throws {
        let model = try UIFixture.sampleModel()
        let gst = model.library.brand.gstRegistered
        model.brandTypingBinding.wrappedValue.businessName = "Sample Studio Two"
        model.brandBinding.wrappedValue.gstRegistered.toggle()
        #expect(model.previewBrand.gstRegistered == !gst)
        #expect(model.previewBrand.businessName == "Sample Studio Two")
        #expect(model.previewBrand == model.library.brand)

        let colour = model.library.brand.accentHex == "#7A1F2B" ? "#2E6B30" : "#7A1F2B"
        model.brandTypingBinding.wrappedValue.details = "1 Sample Street"
        model.brandBinding.wrappedValue.accentHex = colour
        #expect(model.previewBrand.accentHex == colour)
        #expect(model.previewBrand == model.library.brand)

        model.brandTypingBinding.wrappedValue.abn = "12 345 678 901"
        model.choosingFile = .logo
        model.fileChosen(.success(try UIFixture.file("my logo.pdf", model.pdf(model.sampleContent()))))
        #expect(model.library.brand.logoFile != nil)
        #expect(model.previewBrand == model.library.brand)
    }

    // MARK: Where a field lands on the sample

    /// How many pixels of page 1 are the highlight's yellow (#FFF3A0 at 60% on white).
    private func highlightPixels(_ pdf: Data) throws -> Int {
        let page = try #require(PDFDocument(data: pdf)?.page(at: 0))
        let box = page.bounds(for: .mediaBox)
        let width = Int(box.width), height = Int(box.height)
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            page.draw(with: .mediaBox, to: context)
        }
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4)
        where bytes[i] >= 250 && bytes[i + 1] >= 238 && bytes[i + 1] <= 252 && bytes[i + 2] >= 180 && bytes[i + 2] <= 215 {
            count += 1
        }
        return count
    }

    /// The highlight follows the focused field: a field losing focus after the next one gained it
    /// leaves the new one's highlight, and with nothing focused there is none.
    @Test func theHighlightFollowsTheFocusedField() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.brandHighlight == nil)
        model.brandFocus(.businessName, focused: true)
        #expect(model.brandHighlight == .businessName)
        // Tabbing to the ABN: the ABN may report gaining focus before the name reports losing it.
        model.brandFocus(.abn, focused: true)
        model.brandFocus(.businessName, focused: false)
        #expect(model.brandHighlight == .abn)
        model.brandFocus(.abn, focused: false)
        #expect(model.brandHighlight == nil)

        // The logo, fonts and colour have no text field: the pointer over their group, or their file
        // panel, highlights them; a focused field still wins.
        model.brandHover(.logo, hovering: true)
        #expect(model.brandHighlight == .logo)
        model.brandFocus(.hourlyRate, focused: true)
        #expect(model.brandHighlight == .hourlyRate)
        model.brandFocus(.hourlyRate, focused: false)
        model.brandHover(.logo, hovering: false)
        #expect(model.brandHighlight == nil)
        model.choosingFile = .headingFont
        #expect(model.brandHighlight == .headingFont)
        model.choosingFile = nil

        // Leaving the screen clears it.
        model.brandFocus(.details, focused: true)
        model.clearBrandHighlight()
        #expect(model.brandHighlight == nil)
    }

    /// The sample quote carries the highlight; the PDFs of real documents never do.
    @Test func onlyTheSampleIsHighlighted() throws {
        let model = try UIFixture.sampleModel()
        model.brandFocus(.businessName, focused: true)
        let sample = model.pdf(model.sampleContent(), brand: model.previewBrand, highlight: model.brandHighlight)
        #expect(try highlightPixels(sample) > 300)
        #expect(try highlightPixels(model.pdf(model.sampleContent(), brand: model.previewBrand)) == 0)
        // A real quote, with a Brand field focused all the while.
        let quote = try #require(model.library.quotes.first)
        let content = try #require(model.quoteContent(quote.id))
        #expect(try highlightPixels(model.pdf(content)) == 0)
        if let invoice = model.library.invoices.first, let invoiceContent = model.invoiceContent(invoice.id) {
            #expect(try highlightPixels(model.pdf(invoiceContent)) == 0)
        }
    }

    /// What isn't on the sample quote says where it prints instead.
    @Test func fieldsTheSampleDoesNotShowSayWhereTheyPrint() {
        var brand = Brand()
        brand.businessName = "Sample Studio"
        brand.abn = "12 345 678 901"
        #expect(BrandElement.paymentDetails.placementNote(on: brand) == "Prints on invoices only.")
        #expect(BrandElement.invoiceTerms.placementNote(on: brand) == "Prints on invoices only.")
        #expect(BrandElement.paymentDueDays.placementNote(on: brand) == "Sets the due date, which prints on invoices only.")
        #expect(BrandElement.emails.placementNote(on: brand) == "Goes in the Mail draft, not on the PDF.")
        #expect(BrandElement.logo.placementNote(on: brand) == "Once chosen, it prints at the top left of every document.")
        // What the sample shows has no note.
        for element: BrandElement in [.businessName, .abn, .headingFont, .bodyFont, .accentColour, .hourlyRate,
                                      .quoteValidDays, .quoteTerms] {
            #expect(element.placementNote(on: brand) == nil, "\(element)")
        }
        // Empty, it isn't on the sample yet.
        brand.abn = " "
        #expect(BrandElement.abn.placementNote(on: brand) == "Prints under your details on every quote, invoice and receipt once filled in.")
        brand.quoteTerms = ""
        #expect(BrandElement.quoteTerms.placementNote(on: brand) == "Prints on quotes once filled in.")
    }

    /// The Business tab draws with a note showing.
    @Test func theBusinessTabDrawsWithANote() throws {
        let model = try UIFixture.sampleModel()
        model.brandFocus(.paymentDetails, focused: true)
        let rep = Snapshot.render(BrandView(model: model, tab: .business).background(Win95.face),
                                  size: CGSize(width: 980, height: 620), name: "brand-business-note")
        #expect(rep != nil)
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
        #expect(FileChoice.logo.contentTypes == [.png, .jpeg, .svg, .pdf])
        #expect(FileChoice.headingFont.contentTypes == [.font])
        #expect(FileChoice.bodyFont.contentTypes == [.font])
        #expect(FileChoice.returnedQuote.contentTypes == [.pdf])
        #expect(FileChoice.legacyBackup.contentTypes == [.json])
    }

    @Test func theLogoPickerOffersSVGAndTheHintSaysSo() {
        #expect(FileChoice.logo.contentTypes.contains(.svg))
        #expect(UTType.svg.preferredFilenameExtension == "svg")
        #expect(LookTab.logoHint == "PNG, JPG, SVG or PDF. SVG and PDF logos stay sharp at any size.")
    }

    /// An SVG chosen as the logo reaches the logo handler, becomes a PDF in Assets, and is not read as
    /// a returned quote.
    @Test func aChosenSVGLogoBecomesAPDFLogo() throws {
        let model = try UIFixture.sampleModel()
        let quotes = model.library.quotes.count
        model.choosingFile = .logo
        // SwiftUI may close the panel (clearing the choice) before it reports the file.
        model.choosingFile = nil
        model.fileChosen(.success(try UIFixture.file("my logo.svg", UIFixture.svgData())))
        let name = try #require(model.library.brand.logoFile)
        #expect(name.hasPrefix("logo-") && name.hasSuffix(".pdf"))
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        #expect(model.openQuoteID == nil)
        #expect(model.library.quotes.count == quotes)
        let url = try #require(model.logoURL)
        guard case .vector? = Logo(url: url) else {
            Issue.record("The SVG should be kept as a PDF (vector) logo")
            return
        }
        #expect(PDFDocument(url: url)?.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 200, height: 80))
        // Only the PDF is kept: the original SVG stays where the person has it.
        let kept = try FileManager.default.contentsOfDirectory(atPath: model.store.assetsFolder.path)
        #expect(kept == [name])
    }

    @Test func aBrokenSVGIsRefusedWithTheOneNotAnImageBox() throws {
        let model = try UIFixture.sampleModel()
        model.choosingFile = .logo
        model.fileChosen(.success(try UIFixture.file("broken.svg", Data(#"<svg xmlns="http://www.w3.org/2000/svg"><rect"#.utf8))))
        #expect(model.message?.title == "Not an Image")
        #expect(model.message?.text.contains("broken.svg") == true)
        #expect(model.message?.text.contains("SVG") == true)
        #expect(model.library.brand.logoFile == nil)
        #expect(model.dialog == nil)
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: model.store.assetsFolder.path)) ?? []
        #expect(kept.isEmpty)

        // A logo already there stays when a broken SVG is chosen after it.
        model.importLogo(from: try UIFixture.file("logo.png", UIFixture.pngData()))
        let before = try #require(model.library.brand.logoFile)
        model.message = nil
        model.importLogo(from: try UIFixture.file("worse.svg", Data("not a picture".utf8)))
        #expect(model.message?.title == "Not an Image")
        #expect(model.library.brand.logoFile == before)
    }

    /// With the SVG logo set, the Look tab shows it in the logo well (snapshot: brand-look-svg-logo).
    @Test func theLookTabDrawsAnSVGLogo() throws {
        let model = try UIFixture.sampleModel()
        model.importLogo(from: try UIFixture.file("logo.svg", UIFixture.svgData()))
        #expect(model.library.brand.logoFile != nil)
        let rep = try #require(Snapshot.render(BrandView(model: model, tab: .look).background(Win95.face),
                                               size: CGSize(width: 1000, height: 640), name: "brand-look-svg-logo"))
        #expect(Snapshot.hasContent(rep))
        #expect(Snapshot.logoPixels(rep) > 200, "the SVG logo isn't in the logo well")
    }

    /// The same logo on a rendered quote page (snapshot: quote-page-svg-logo), through the real chain:
    /// the Assets file, the brand's look, the renderer.
    @Test func aQuotePageDrawsTheSVGLogoAtTheTop() throws {
        let model = try UIFixture.sampleModel()
        let plain = try #require(Snapshot.renderPage(model.pdf(model.sampleContent()), name: "quote-page-no-logo"))
        #expect(Snapshot.logoPixels(plain) == 0)

        model.importLogo(from: try UIFixture.file("logo.svg", UIFixture.svgData()))
        let data = model.pdf(model.sampleContent())
        let page = try #require(Snapshot.renderPage(data, name: "quote-page-svg-logo"))
        #expect(Snapshot.hasContent(page))
        // At 2 pixels to the point, the logo is in the top 300 pixels, and about 66 x 40 points big.
        #expect(Snapshot.logoPixels(page, rows: 300) > 6_000)
        #expect(Snapshot.logoPixels(page, rows: 300) == Snapshot.logoPixels(page))
        #expect(!String(decoding: data, as: UTF8.self).contains("/Subtype /Image"))
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
    /// the tab strip (24) and the panel's padding (20): 432. With the Body font group the Look tab
    /// (Logo, Hourly rate, Heading font, Body font, Accent colour) is taller than that, whether or not
    /// a font is chosen, so it scrolls: nothing may be cut off, so the tab must sit in a vertical
    /// scroll view that holds all of it (at the narrowest the tab column goes: 460 less the panel's
    /// padding and the scroller's gap).
    @Test func theLookTabScrollsInTheSmallestWindowSoEveryGroupCanBeReached() throws {
        let model = try UIFixture.sampleModel()
        _ = NSApplication.shared
        let look = LookTab(model: model, brand: model.brandBinding).groupBoxStyle(.win95)
        let needed = NSHostingView(rootView: look.frame(width: 460 - 20 - 6)).fittingSize.height

        let size = CGSize(width: 778, height: 492)
        let host = NSHostingView(rootView: BrandView(model: model, tab: .look).background(Win95.face)
            .frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        func scrollViews(in view: NSView) -> [NSScrollView] {
            var found = (view as? NSScrollView).map { [$0] } ?? []
            for subview in view.subviews { found += scrollViews(in: subview) }
            return found
        }
        // The tab's scroll view is the one that scrolls up and down and is tall enough for the groups.
        let tab = try #require(scrollViews(in: host).first { $0.hasVerticalScroller && ($0.documentView?.frame.height ?? 0) >= needed })
        let document = try #require(tab.documentView)
        #expect(document.frame.height > tab.contentSize.height, "taller than the \(tab.contentSize.height) it shows, so it scrolls")
        #expect(document.frame.height >= needed)
    }
}
