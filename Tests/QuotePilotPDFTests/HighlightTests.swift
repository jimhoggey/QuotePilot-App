import AppKit
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

/// The Brand screen's highlight: drawn only when asked, behind the element being edited.
@Suite struct HighlightTests {
    let quote = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)

    /// Page 1 at one pixel a point, on white: RGBA bytes, top row first.
    static func pixels(_ data: Data) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let page = try #require(PDFDocument(data: data)?.page(at: 0))
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
        return (bytes, width, height)
    }

    /// #FFF3A0 at 60% on white is about (255, 248, 198).
    static func isHighlight(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
        r >= 250 && g >= 238 && g <= 252 && b >= 180 && b <= 215
    }

    /// How many pixels of page 1 are the highlight's yellow.
    static func highlightPixels(_ data: Data) throws -> Int {
        let (bytes, width, height) = try pixels(data)
        var count = 0
        for i in stride(from: 0, to: width * height * 4, by: 4) where isHighlight(bytes[i], bytes[i + 1], bytes[i + 2]) {
            count += 1
        }
        return count
    }

    /// The colour at a point given in PDF coordinates (origin bottom left).
    static func color(_ data: Data, at point: CGPoint) throws -> (r: UInt8, g: UInt8, b: UInt8) {
        let (bytes, width, height) = try pixels(data)
        let i = ((height - 1 - Int(point.y)) * width + Int(point.x)) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }

    @Test func theBusinessNameIsHighlightedOnlyWhenAsked() throws {
        let plain = DocumentRenderer.render(quote, style: PDFStyle())
        let marked = DocumentRenderer.render(quote, style: PDFStyle(), highlight: .businessName)
        let document = try #require(PDFDocument(data: marked))
        // The first "Sample Studio" from the top is the name in the header (the footer has it too).
        let name = try #require(LayoutTests.bounds(of: "Sample Studio", in: document).first)
        // Just left of the name, inside the highlight's margin: yellow, and white without it.
        let beside = CGPoint(x: name.minX - 1.5, y: name.midY)
        let yellow = try Self.color(marked, at: beside)
        #expect(Self.isHighlight(yellow.r, yellow.g, yellow.b), "\(yellow)")
        let white = try Self.color(plain, at: beside)
        #expect(white.r == 255 && white.g == 255 && white.b == 255, "\(white)")
        // Behind the name, not over it: the name is still dark ink.
        let page = try #require(Ink(page: 0, of: marked, scale: 2))
        #expect(page.lowestInk(in: name) != nil)
        // Nothing else is marked: not the client, not the quote's number.
        let client = try #require(LayoutTests.bounds(of: "Sample Client Pty Ltd", in: document).first)
        let other = try Self.color(marked, at: CGPoint(x: client.minX - 1.5, y: client.midY))
        #expect(!Self.isHighlight(other.r, other.g, other.b))
        // And without being asked, the page has no highlight at all.
        #expect(try Self.highlightPixels(plain) == 0)
        #expect(try Self.highlightPixels(marked) > 300)
    }

    /// Each part of the brand that a quote shows is marked; the ones only invoices or emails carry
    /// mark nothing on a quote, and do on an invoice.
    @Test func eachElementIsMarkedWhereTheDocumentShowsIt() throws {
        let onQuote: [BrandElement] = [.businessName, .details, .abn, .headingFont, .bodyFont, .accentColour,
                                       .hourlyRate, .quoteValidDays, .quoteTerms]
        for element in onQuote {
            let data = DocumentRenderer.render(quote, style: PDFStyle(), highlight: element)
            #expect(try Self.highlightPixels(data) > 100, "\(element) isn't marked on the quote")
        }
        for element: BrandElement in [.paymentDetails, .invoiceTerms, .paymentDueDays, .emails, .logo] {
            let data = DocumentRenderer.render(quote, style: PDFStyle(), highlight: element)
            #expect(try Self.highlightPixels(data) == 0, "\(element) is marked on a quote")
        }
        var invoice = Sample.invoice(.standalone)
        invoice.terms = "Please use the invoice number as your payment reference."
        let content = DocumentContent.invoice(invoice, client: Sample.client, brand: Sample.brand, quoteNumber: nil)
        for element: BrandElement in [.paymentDetails, .invoiceTerms, .paymentDueDays] {
            let data = DocumentRenderer.render(content, style: PDFStyle(), highlight: element)
            #expect(try Self.highlightPixels(data) > 100, "\(element) isn't marked on the invoice")
        }
    }

    /// The ABN and the details above it are marked apart.
    @Test func theABNIsMarkedApartFromTheDetails() throws {
        let data = DocumentRenderer.render(quote, style: PDFStyle(), highlight: .abn)
        let document = try #require(PDFDocument(data: data))
        let abn = try #require(LayoutTests.bounds(of: "ABN 00 000 000 000", in: document).first)
        let email = try #require(LayoutTests.bounds(of: "hello@example.com", in: document).first)
        let atABN = try Self.color(data, at: CGPoint(x: abn.minX - 1.5, y: abn.midY))
        let atEmail = try Self.color(data, at: CGPoint(x: email.minX - 1.5, y: email.midY))
        #expect(Self.isHighlight(atABN.r, atABN.g, atABN.b))
        #expect(!Self.isHighlight(atEmail.r, atEmail.g, atEmail.b))
    }

    /// A highlight changes nothing else about the document: same text, same form.
    @Test func aHighlightLeavesTheFormAndTextAlone() throws {
        let marked = try #require(PDFDocument(data: DocumentRenderer.render(quote, style: PDFStyle(), highlight: .quoteTerms)))
        let plain = Sample.pdf(quote)
        #expect(Sample.text(marked) == Sample.text(plain))
        let names = { (document: PDFDocument) in
            Set((0..<document.pageCount).flatMap { document.page(at: $0)!.annotations }.compactMap(\.fieldName))
        }
        #expect(names(marked) == names(plain))
        #expect(names(marked).count == 6)
    }
}
