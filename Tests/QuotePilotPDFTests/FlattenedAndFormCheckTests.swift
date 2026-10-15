import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

@Suite struct FlattenedAndFormCheckTests {
    func quotePDF() -> Data {
        DocumentRenderer.render(.quote(Sample.quote(), client: Sample.client, brand: Sample.brand), style: PDFStyle())
    }

    /// Draws page 1 into a new PDF, the way printing to PDF does, keeping only the info given.
    func flattened(_ data: Data, info: [CFString: Any]? = nil) -> Data {
        let document = PDFDocument(data: data)!
        let flat = NSMutableData()
        var box = CGRect(origin: .zero, size: PageWriter.pageSize)
        let context = CGContext(consumer: CGDataConsumer(data: flat as CFMutableData)!, mediaBox: &box,
                                info as CFDictionary?)!
        context.beginPDFPage(nil)
        document.page(at: 0)!.draw(with: .mediaBox, to: context)
        context.endPDFPage()
        context.closePDF()
        return flat as Data
    }

    @Test func aRenderedQuoteHasItsForm() {
        #expect(DocumentRenderer.hasForm(quotePDF(), quoteNumber: "Q-0001"))
        #expect(!DocumentRenderer.hasForm(quotePDF(), quoteNumber: "Q-0002"))
    }

    @Test func aFlattenedQuoteOrAnInvoiceHasNone() {
        #expect(!DocumentRenderer.hasForm(flattened(quotePDF()), quoteNumber: "Q-0001"))
        let invoice = DocumentRenderer.render(.invoice(Sample.invoice(.standalone), client: Sample.client,
                                                       brand: Sample.brand, quoteNumber: nil), style: PDFStyle())
        #expect(!DocumentRenderer.hasForm(invoice, quoteNumber: "Q-0001"))
        #expect(!DocumentRenderer.hasForm(Data("hello".utf8), quoteNumber: "Q-0001"))
    }

    /// The release-build fallback: the widgets are on the page, but the catalog has no AcroForm, so
    /// other viewers wouldn't fill them. Only the "/AcroForm" byte check tells these apart.
    @Test func widgetsWithoutAnAcroFormAreNotAForm() {
        var data = quotePDF()
        while let range = data.range(of: Data("/AcroForm".utf8)) {
            data.replaceSubrange(range, with: Data("/AcroFxrm".utf8))
        }
        // The widgets are still there, so only the missing AcroForm can make this false.
        let widgets = PDFDocument(data: data)?.page(at: 0)?.annotations ?? []
        #expect(widgets.contains { $0.fieldName == QuoteFormFields.acceptAll("Q-0001") })
        #expect(!DocumentRenderer.hasForm(data, quoteNumber: "Q-0001"))
    }

    @Test func theQuoteNumberComesFromTheKeywords() {
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: quotePDF()) == "Q-0001")
        let kept = flattened(quotePDF(), info: [kCGPDFContextKeywords: ["quotepilot", "Q-0001"]])
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: kept) == "Q-0001")
    }

    /// Keywords separated by a semicolon or a comma, not only a comma and a space, still name the quote.
    @Test func keywordsSeparatedBySemicolonsOrCommasStillName() {
        let semicolon = flattened(quotePDF(), info: [kCGPDFContextKeywords: "quotepilot;Q-0001"])
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: semicolon) == "Q-0001")
        let comma = flattened(quotePDF(), info: [kCGPDFContextKeywords: "quotepilot,Q-0001"])
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: comma) == "Q-0001")
    }

    @Test func aPDFWithoutQuotePilotKeywordsNamesNoQuote() {
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: flattened(quotePDF())) == nil)
        let other = flattened(quotePDF(), info: [kCGPDFContextKeywords: ["Q-0001"]])
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: other) == nil)
        #expect(ReturnedQuoteReader.quoteNumber(inMetadataOf: Data("hello".utf8)) == nil)
    }
}
