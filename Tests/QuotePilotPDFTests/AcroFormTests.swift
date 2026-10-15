import CoreGraphics
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

/// The quote form has to work outside Apple's apps too (Chrome, Edge, Acrobat), which need a complete
/// /AcroForm in the catalog and a font they can resolve. These look at the PDF's bytes, not at PDFKit.
@Suite struct AcroFormTests {
    private func renderedQuote() -> Data {
        DocumentRenderer.render(DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand),
                                style: PDFStyle())
    }

    /// One byte per character, so string offsets are byte offsets.
    private func latin1(_ data: Data) -> String {
        String(data: data, encoding: .isoLatin1)!
    }

    private func matches(_ pattern: String, in text: String) -> [[String]] {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    /// Object numbers of every widget dictionary in the file, found by scanning the objects.
    private func widgetObjectNumbers(_ text: String) -> [Int] {
        matches(#"(\d+) 0 obj\s*<<((?:(?!endobj).)*?)>>\s*endobj"#, in: text)
            .filter { $0[2].contains("/Subtype /Widget") }
            .compactMap { Int($0[1]) }
            .sorted()
    }

    @Test func aQuoteHasACompleteAcroFormListingEverySixFields() throws {
        let text = latin1(renderedQuote())
        #expect(text.contains("/AcroForm"))
        let widgets = widgetObjectNumbers(text)
        #expect(widgets.count == 6)  // all, 01, 02, 03, name, date
        let fields = try #require(matches(#"/Fields\s*\[([^\]]*)\]"#, in: text).last)
        let listed = matches(#"(\d+) 0 R"#, in: fields[1]).compactMap { Int($0[1]) }
        #expect(listed.sorted() == widgets)
        #expect(Set(listed).count == listed.count)
    }

    @Test func theAcroFormAsksViewersToDrawFieldsAndDeclaresHelvetica() {
        let text = latin1(renderedQuote())
        #expect(text.contains("/NeedAppearances true"))
        #expect(text.contains("/BaseFont /Helvetica"))
        #expect(text.contains("/DR"))
    }

    @Test func noFieldNamesAFontOnlyAppleCanResolve() {
        let text = latin1(renderedQuote())
        let defaults = matches(#"/DA \(([^)]*)\)"#, in: text).map { $0[1] }
        #expect(defaults.count >= 6)
        for da in defaults {
            #expect(!da.contains("AppleSystemUIFont"), "default appearance \(da)")
        }
    }

    @Test func theAcroFormIsReachableFromTheCatalogByAnotherReader() throws {
        // Core Graphics reads through the cross-reference table, so this proves the update is well formed.
        let provider = try #require(CGDataProvider(data: renderedQuote() as CFData))
        let document = try #require(CGPDFDocument(provider))
        let catalog = try #require(document.catalog)
        var acroForm: CGPDFDictionaryRef?
        #expect(CGPDFDictionaryGetDictionary(catalog, "AcroForm", &acroForm))
        var fields: CGPDFArrayRef?
        #expect(CGPDFDictionaryGetArray(try #require(acroForm), "Fields", &fields))
        #expect(CGPDFArrayGetCount(try #require(fields)) == 6)
        #expect(document.numberOfPages == 1)
    }

    @Test func theUpdateIsAppendedAndItsCrossReferenceIsExact() throws {
        let original = renderedQuoteWithoutAcroForm()
        let updated = try #require(AcroFormWriter.addingAcroForm(to: original))
        #expect(updated.prefix(original.count) == original)  // an incremental update never rewrites the file
        let text = latin1(updated)
        // NSString offsets count UTF-16 units, which is one per byte here; Swift Characters would not
        // (a "\r\n" in binary stream data is a single Character).
        let bytes = text as NSString
        let startxref = try #require(matches(#"startxref\s+(\d+)\s+%%EOF\s*$"#, in: text).last)
        let offset = try #require(Int(startxref[1]))
        #expect(offset >= original.count)
        let tail = bytes.substring(from: offset)
        #expect(tail.hasPrefix("xref\n"))
        #expect(tail.contains("/Prev"))
        // Every 20-byte entry in the new section points at "<n> 0 obj".
        var number = 0
        var entries = 0
        for line in tail.components(separatedBy: "\n").dropFirst() {
            if line.hasPrefix("trailer") { break }
            let parts = line.split(separator: " ")
            if parts.count == 2, let first = Int(parts[0]) { number = first; continue }
            if parts.count == 3, parts[2] == "n", let at = Int(parts[0]) {
                #expect(line.utf8.count + 1 == 20)
                #expect(bytes.substring(from: at).hasPrefix("\(number) 0 obj"), "object \(number) at \(at)")
                number += 1
                entries += 1
            }
        }
        #expect(entries == 3)  // the new catalog, the AcroForm and its font
    }

    @Test func theFormStillOpensWithAllSixNamesAndEveryBoxOff() throws {
        let document = try #require(PDFDocument(data: renderedQuote()))
        #expect(document.pageCount == 1)
        let widgets = document.page(at: 0)!.annotations.filter { $0.fieldName != nil }
        let expected: Set<String> = [
            QuoteFormFields.acceptAll("Q-0001"),
            QuoteFormFields.line("Q-0001", "01"), QuoteFormFields.line("Q-0001", "02"), QuoteFormFields.line("Q-0001", "03"),
            QuoteFormFields.name("Q-0001"), QuoteFormFields.date("Q-0001"),
        ]
        #expect(Set(widgets.compactMap(\.fieldName)) == expected)
        #expect(widgets.filter { $0.widgetFieldType == .button }.allSatisfy { $0.buttonWidgetState == .offState })
    }

    @Test func invoicesAndReceiptsGetNoAcroForm() {
        let invoice = DocumentRenderer.render(
            DocumentContent.invoice(Sample.invoice(.standalone), client: Sample.client, brand: Sample.brand, quoteNumber: nil),
            style: PDFStyle())
        #expect(!latin1(invoice).contains("/AcroForm"))
    }

    @Test func somethingThatIsNotAPDFIsRefused() {
        #expect(AcroFormWriter.addingAcroForm(to: Data("not a pdf".utf8)) == nil)
    }

    @Test func aPDFWithoutWidgetsIsRefused() {
        let invoice = DocumentRenderer.render(
            DocumentContent.invoice(Sample.invoice(.standalone), client: Sample.client, brand: Sample.brand, quoteNumber: nil),
            style: PDFStyle())
        #expect(AcroFormWriter.addingAcroForm(to: invoice) == nil)
    }

    /// The same quote as PDFKit wrote it, before the AcroForm update.
    private func renderedQuoteWithoutAcroForm() -> Data {
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: PageWriter.pageSize)
        let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        let writer = PageWriter(context: context)
        let layout = Layout(content: content, style: PDFStyle(), writer: writer)
        layout.drawAll()
        writer.finish()
        return DocumentRenderer.addForm(layout.fields, to: data as Data, content: content)
    }
}
