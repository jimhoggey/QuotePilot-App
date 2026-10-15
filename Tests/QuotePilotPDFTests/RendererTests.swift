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
        #expect(!text.contains("ABN"))
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

    @Test func taxedInvoicesAreTaxInvoicesWithTheABN() {
        let content = DocumentContent.invoice(Sample.invoice(.standalone, taxed: true), client: Sample.client,
                                              brand: Sample.brand, quoteNumber: nil)
        #expect(content.title == "Tax invoice")
        #expect(content.totals.map(\.label) == ["Subtotal", "GST (10%)", "Total (AUD)"])
        #expect(content.amount == "$1,188.00")
        #expect(Sample.text(Sample.pdf(content)).contains("ABN 00 000 000 000"))
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
