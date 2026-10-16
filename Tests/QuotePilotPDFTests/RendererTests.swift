import AppKit
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

@Suite struct RendererTests {
    @Test func aQuoteShowsEverythingTheClientNeeds() {
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        #expect(content.fileName == "Q-0001 Sample Client Pty Ltd.pdf")
        #expect(content.amount == "$1,500.00")
        #expect(content.formQuoteNumber == "Q-0001")
        let document = Sample.pdf(content)
        #expect(document.pageCount == 1)
        let text = Sample.text(document)
        for expected in ["Quote", "Q-0001", "Sample Studio", "Sample Client Pty Ltd", "Discovery", "2 hrs",
                         "$1,500.00", "Accept all", "Accepted by", "Work summary", "Payment plan",
                         "50% when the quote is accepted"] {
            #expect(text.contains(expected), "missing \(expected)")
        }
        // The brand has an ABN, so the quote carries it, though it has no GST.
        #expect(text.contains("ABN 00 000 000 000"))
    }

    @Test func aDepositInvoiceBillsTheShare() {
        var invoice = Sample.invoice(.deposit)
        invoice.depositPercent = 50
        let content = DocumentContent.invoice(invoice, client: Sample.client, brand: Sample.brand, quoteNumber: "Q-0001")
        #expect(content.title == "Invoice")
        #expect(content.amount == "$540.00")
        #expect(content.totals.map(\.label) == ["Accepted total", "Deposit (50%)"])
        let text = Sample.text(Sample.pdf(content))
        #expect(text.contains("Deposit (50%)"))
        #expect(text.contains("BSB 000-000"))
        #expect(text.contains("Due 29 October 2026"))
    }

    @Test func aFinalInvoiceSubtractsTheDeposit() {
        var invoice = Sample.invoice(.final)
        invoice.deductions = [Deduction(label: "Less deposit", invoiceNumber: "INV-0000", amount: Money(dollars: 540))]
        let content = DocumentContent.invoice(invoice, client: Sample.client, brand: Sample.brand, quoteNumber: "Q-0001")
        #expect(content.totals.map(\.label) == ["Accepted total", "Less deposit, INV-0000", "Balance (AUD)"])
        #expect(content.amount == "$540.00")
    }

    @Test func aFullInvoiceThatSubtractsADepositShowsTheSubtraction() {
        // Only reachable if a deposit exists when the plan says "full amount", but the PDF must still add up.
        var invoice = Sample.invoice(.full)
        let plain = DocumentContent.invoice(invoice, client: Sample.client, brand: Sample.brand, quoteNumber: "Q-0001")
        #expect(plain.totals.map(\.label) == ["Total (AUD)"])
        invoice.deductions = [Deduction(label: "Less deposit", invoiceNumber: "INV-0000", amount: Money(dollars: 540))]
        let content = DocumentContent.invoice(invoice, client: Sample.client, brand: Sample.brand, quoteNumber: "Q-0001")
        #expect(content.totals.map(\.label) == ["Accepted total", "Less deposit, INV-0000", "Balance (AUD)"])
        #expect(content.amount == "$540.00")
    }

    @Test func taxedInvoicesAreTaxInvoicesWithTheABN() {
        let content = DocumentContent.invoice(Sample.invoice(.standalone, taxed: true), client: Sample.client,
                                              brand: Sample.brand, quoteNumber: nil)
        #expect(content.title == "Tax invoice")
        #expect(content.totals.map(\.label) == ["Subtotal", "GST (10%)", "Total (AUD)"])
        #expect(content.amount == "$1,188.00")
        #expect(Sample.text(Sample.pdf(content)).contains("ABN 00 000 000 000"))
    }

    // MARK: The ABN

    /// GST off: still an "Invoice", with no GST lines, but the ABN prints with the business details.
    @Test func anInvoiceWithoutGSTStillShowsTheABN() {
        var brand = Sample.brand
        brand.abn = "12345678901"
        let content = DocumentContent.invoice(Sample.invoice(.standalone), client: Sample.client, brand: brand, quoteNumber: nil)
        #expect(content.title == "Invoice")
        #expect(content.totals.map(\.label) == ["Total (AUD)"])
        #expect(content.fromDetails == "hello@example.com\n0400 000 000\nABN 12 345 678 901")
        let text = Sample.text(Sample.pdf(content))
        #expect(text.contains("ABN 12 345 678 901"))
        #expect(!text.contains("Tax invoice"))
        #expect(!text.contains("GST"))
    }

    /// Quotes and receipts carry it too, whether or not the document has GST.
    @Test func quotesAndReceiptsShowTheABNWithOrWithoutGST() {
        var brand = Sample.brand
        brand.abn = "12 345 678 901"
        var receipted = Sample.invoice(.standalone)
        receipted.payments = [Payment(date: Sample.today, amount: Money(dollars: 100))]
        var taxedQuote = Sample.quote()
        taxedQuote.taxed = true
        let documents: [DocumentContent] = [
            .quote(Sample.quote(), client: Sample.client, brand: brand),
            .quote(taxedQuote, client: Sample.client, brand: brand),
            .receipt(receipted, client: Sample.client, brand: brand),
        ]
        for content in documents {
            #expect(content.fromDetails.hasSuffix("\nABN 12 345 678 901"), "\(content.title)")
            #expect(Sample.text(Sample.pdf(content)).contains("ABN 12 345 678 901"), "\(content.title)")
        }
    }

    /// No ABN on the brand: no "ABN" line anywhere, taxed or not.
    @Test func anEmptyABNPrintsNothing() {
        var brand = Sample.brand
        brand.abn = "   "
        var receipted = Sample.invoice(.standalone, taxed: true)
        receipted.payments = [Payment(date: Sample.today, amount: Money(dollars: 100))]
        let documents: [DocumentContent] = [
            .quote(Sample.quote(), client: Sample.client, brand: brand),
            .invoice(Sample.invoice(.standalone), client: Sample.client, brand: brand, quoteNumber: nil),
            .invoice(Sample.invoice(.standalone, taxed: true), client: Sample.client, brand: brand, quoteNumber: nil),
            .receipt(receipted, client: Sample.client, brand: brand),
        ]
        for content in documents {
            #expect(content.fromDetails == "hello@example.com\n0400 000 000", "\(content.title)")
            #expect(!Sample.text(Sample.pdf(content)).contains("ABN"), "\(content.title)")
        }
    }

    @Test func anABNOfElevenDigitsIsGroupedTwoThreeThreeThree() {
        #expect(DocumentContent.formattedABN("12345678901") == "12 345 678 901")
        #expect(DocumentContent.formattedABN(" 12 345 678 901 ") == "12 345 678 901")
        #expect(DocumentContent.formattedABN("123 456 789 01") == "12 345 678 901")
        // Anything else prints as typed.
        #expect(DocumentContent.formattedABN("1234567890") == "1234567890")
        #expect(DocumentContent.formattedABN("123456789012") == "123456789012")
        #expect(DocumentContent.formattedABN("12-345-678-901") == "12-345-678-901")
        #expect(DocumentContent.formattedABN("Applied for") == "Applied for")
    }

    @Test func aReceiptListsThePayments() {
        var invoice = Sample.invoice(.standalone)
        invoice.payments = [Payment(date: Sample.today.adding(days: 2), amount: Money(dollars: 1080))]
        let content = DocumentContent.receipt(invoice, client: Sample.client, brand: Sample.brand)
        #expect(content.title == "Receipt")
        #expect(content.amountNote == "Paid in full. Thank you.")
        #expect(content.fileName == "Receipt INV-0001 Sample Client Pty Ltd.pdf")
        #expect(Sample.text(Sample.pdf(content)).contains("Paid 17 Oct 2026, bank transfer"))
    }

    @Test func invoicesHaveNoForm() {
        let document = Sample.pdf(DocumentContent.invoice(Sample.invoice(.standalone), client: Sample.client,
                                                          brand: Sample.brand, quoteNumber: nil))
        let widgets = (0..<document.pageCount).flatMap { document.page(at: $0)!.annotations }
        #expect(widgets.isEmpty)
    }

    /// Every named form widget in the document, across all pages.
    private func widgets(_ document: PDFDocument) -> [PDFAnnotation] {
        (0..<document.pageCount).flatMap { document.page(at: $0)!.annotations }.filter { $0.fieldName != nil }
    }

    @Test func aQuoteFormHasAFieldForEachLineAndTheSignOff() {
        let document = Sample.pdf(DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand))
        let names = widgets(document).compactMap(\.fieldName)
        let expected: Set<String> = [
            QuoteFormFields.acceptAll("Q-0001"),
            QuoteFormFields.line("Q-0001", "01"), QuoteFormFields.line("Q-0001", "02"), QuoteFormFields.line("Q-0001", "03"),
            QuoteFormFields.name("Q-0001"), QuoteFormFields.date("Q-0001"),
        ]
        #expect(names.count == expected.count)
        #expect(Set(names) == expected)
        #expect(names.allSatisfy { QuoteFormFields.parse($0)?.quote == "Q-0001" })
    }

    @Test func fieldNamesInTheFileUseUnderscoresNotDots() {
        // PDF reserves "." for field hierarchy, so a dotted name could be split up when a client saves.
        let document = Sample.pdf(DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand))
        let names = Set(widgets(document).compactMap(\.fieldName))
        #expect(names == [
            "quotepilot_Q-0001_all",
            "quotepilot_Q-0001_line_01", "quotepilot_Q-0001_line_02", "quotepilot_Q-0001_line_03",
            "quotepilot_Q-0001_name", "quotepilot_Q-0001_date",
        ])
        #expect(names.allSatisfy { !$0.contains(".") })
    }

    @Test func everyTickBoxStartsOff() {
        let document = Sample.pdf(DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand))
        let boxes = widgets(document).filter { $0.widgetFieldType == .button }
        #expect(boxes.count == 4)
        #expect(boxes.allSatisfy { $0.buttonWidgetState == .offState })
    }

    @Test func aTickedBoxAndTypedNameSurviveSavingThePDF() throws {
        let document = Sample.pdf(DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand))
        for widget in widgets(document) {
            switch widget.fieldName {
            case QuoteFormFields.line("Q-0001", "02"): widget.buttonWidgetState = .onState
            case QuoteFormFields.name("Q-0001"): widget.widgetStringValue = "Sam Example"
            default: break
            }
        }
        let data = try #require(document.dataRepresentation())
        let saved = try #require(PDFDocument(data: data))
        let byName = Dictionary(uniqueKeysWithValues: widgets(saved).map { ($0.fieldName!, $0) })
        #expect(byName[QuoteFormFields.line("Q-0001", "02")]?.buttonWidgetState == .onState)
        #expect(byName[QuoteFormFields.line("Q-0001", "01")]?.buttonWidgetState == .offState)
        #expect(byName[QuoteFormFields.name("Q-0001")]?.widgetStringValue == "Sam Example")
    }

    @Test func aLongQuoteRunsOntoMoreRepeatingItsHeaderAndKeepsEveryTickBox() {
        let document = Sample.pdf(DocumentContent.quote(Sample.quote(extraLines: 40), client: Sample.client, brand: Sample.brand))
        #expect(document.pageCount > 1)
        let text = Sample.text(document)
        #expect(text.contains("Quote Q-0001, continued"))
        #expect(text.contains("Item 043"))
        let names = widgets(document).compactMap(\.fieldName)
        // Accept all, 43 lines, name and date.
        #expect(names.count == 46)
        #expect(Set(names).count == 46)
        #expect(names.allSatisfy { QuoteFormFields.parse($0)?.quote == "Q-0001" })
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: "/System/Library/Fonts/Supplemental/Georgia.ttf")))
    func theBrandsHeadingFontIsEmbedded() {
        let style = PDFStyle(headingFontURL: URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/Georgia.ttf"))
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        let data = DocumentRenderer.render(content, style: style)
        #expect(String(decoding: data, as: UTF8.self).contains("Georgia"))
    }

    @Test func aLogoIsDrawn() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("logo-\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: 120, height: 40), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: url)
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        let plain = DocumentRenderer.render(content, style: PDFStyle())
        let branded = DocumentRenderer.render(content, style: PDFStyle(logo: Logo(url: url)))
        #expect(Logo(url: url) != nil)
        #expect(branded.count > plain.count)
    }

    @Test func coloursComeFromHex() {
        // Spelled out as a typed constant: Swift 6.4 can't type-check this array inside #expect in time.
        let expected: [CGFloat] = [11.0 / 255, 107.0 / 255, 102.0 / 255, 1]
        #expect(PDFStyle.color(hex: "#0B6B66")?.components == expected)
        #expect(PDFStyle.color(hex: "nope") == nil)
    }
}
