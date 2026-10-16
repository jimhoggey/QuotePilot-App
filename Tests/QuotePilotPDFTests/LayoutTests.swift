import AppKit
import Foundation
import PDFKit
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

/// Where things land on the page: columns, baselines, page breaks. Positions come from PDFKit's
/// reading of the rendered text, in PDF points (origin bottom left).
@Suite struct LayoutTests {
    /// Every place `text` is drawn on page `page`, left to right then top down.
    static func bounds(of text: String, in document: PDFDocument, page index: Int = 0) -> [CGRect] {
        guard let page = document.page(at: index) else { return [] }
        return document.findString(text, withOptions: .literal)
            .filter { $0.pages.first === page }
            .map { $0.bounds(for: page) }
            .sorted { abs($0.midY - $1.midY) > 2 ? $0.midY > $1.midY : $0.minX < $1.minX }
    }

    /// The made-up invoice with one big line: 2.5 days at $987,654.32.
    static func bigInvoice() -> DocumentContent {
        let invoice = Invoice(number: "INV-0001", kind: .standalone, issued: Sample.today, due: Sample.today.adding(days: 14),
                              lines: [LineItem(title: "Warehouse fit-out", quantity: Decimal(string: "2.5")!, unit: .days,
                                               rate: Money(dollars: 987_654, cents: 32))],
                              stage: .sent)
        return .invoice(invoice, client: Sample.client, brand: Sample.brand, quoteNumber: nil)
    }

    // MARK: The line table's columns

    /// A total in the millions widens the Rate and Amount columns rather than running into the
    /// column beside it.
    @Test func amountsInTheMillionsDoNotRunIntoTheNextColumn() throws {
        let content = Self.bigInvoice()
        #expect(content.rows.first?.rate == "$987,654.32")
        #expect(content.rows.first?.amount == "$2,469,135.80")
        let document = Sample.pdf(content)

        let qty = try #require(Self.bounds(of: "2.5 days", in: document).first)
        let rate = try #require(Self.bounds(of: "$987,654.32", in: document).first)
        let amounts = Self.bounds(of: "$2,469,135.80", in: document)
        // The big amount at the top, the line's amount, and the total.
        #expect(amounts.count == 3)
        let amount = try #require(amounts.first { abs($0.midY - rate.midY) < 2 })
        #expect(abs(qty.midY - rate.midY) < 2)
        #expect(rate.minX - qty.maxX >= 10, "Qty and Rate touch: \(qty) \(rate)")
        #expect(amount.minX - rate.maxX >= 10, "Rate and Amount touch: \(rate) \(amount)")
        // Every amount ends on the same right edge, the line's and the total's alike.
        let total = try #require(amounts.last)
        #expect(total.midY < amount.midY)
        #expect(abs(total.maxX - amount.maxX) < 0.5)
        #expect(abs(amount.maxX - (PageWriter.pageSize.width - PageWriter.margin)) < 1)
    }

    /// Ordinary figures keep the usual column widths, so the description keeps its room.
    @Test func ordinaryFiguresKeepTheUsualColumns() throws {
        let context = CGContext(consumer: CGDataConsumer(data: NSMutableData() as CFMutableData)!, mediaBox: nil, nil)!
        let writer = PageWriter(context: context)
        let quote = Layout(content: .quote(Sample.quote(), client: Sample.client, brand: Sample.brand),
                           style: PDFStyle(), writer: writer)
        #expect(quote.columnRights.amount == writer.right)
        #expect(quote.columnRights.rate == writer.right - Layout.amountColumn)
        #expect(quote.columnRights.qty == writer.right - Layout.amountColumn - Layout.rateColumn)
        #expect(quote.descriptionColumn.width == quote.columnRights.qty - Layout.qtyColumn - quote.descriptionColumn.x)

        let big = Layout(content: Self.bigInvoice(), style: PDFStyle(), writer: writer)
        #expect(big.columnRights.rate < writer.right - Layout.amountColumn)
        #expect(big.descriptionColumn.width < writer.width - Layout.qtyColumn - Layout.rateColumn - Layout.amountColumn)
    }

    // MARK: The right-hand column

    /// The document's details, the totals and the Accepted by date all start on one line.
    @Test func detailsTotalsAndTheDateFieldShareALeftEdge() throws {
        let data = DocumentRenderer.render(.quote(Sample.quote(), client: Sample.client, brand: Sample.brand), style: PDFStyle())
        let document = try #require(PDFDocument(data: data))
        let column = PageWriter.pageSize.width - PageWriter.margin - Layout.rightColumnWidth
        let details = try #require(Self.bounds(of: "Quote no.", in: document).first)
        let total = try #require(Self.bounds(of: "Total (AUD)", in: document).first)
        let date = try #require(document.page(at: 0)?.annotations.first { $0.fieldName == QuoteFormFields.date("Q-0001") })
        #expect(abs(details.minX - column) < 1.5)
        #expect(abs(total.minX - column) < 1.5)
        #expect(abs(date.bounds.minX - column) < 0.5, "\(date.bounds.minX) against \(column)")
        // The client and the name field stop short of it.
        let name = try #require(document.page(at: 0)?.annotations.first { $0.fieldName == QuoteFormFields.name("Q-0001") })
        #expect(name.bounds.maxX <= column - Layout.columnGutter + 0.5, "\(name.bounds.maxX)")
    }

    /// A totals label too long for the room its amount leaves wraps, and the next line moves down
    /// to clear it.
    @Test func aLongTotalsLabelWrapsClearOfItsAmount() throws {
        var invoice = Sample.invoice(.standalone)
        invoice.payments = [Payment(date: Sample.today, amount: Money(dollars: 1_080))]
        var content = DocumentContent.receipt(invoice, client: Sample.client, brand: Sample.brand)
        content.totals[1].label = "Paid 15 October 2026 by bank transfer from the client's trust account"
        content.totals[1].value = "$1,234,567.89"
        let document = Sample.pdf(content)
        let words = try #require(Self.bounds(of: "Paid 15 October", in: document).first)
        let end = try #require(Self.bounds(of: "account", in: document).first)
        let value = try #require(Self.bounds(of: "$1,234,567.89", in: document).first)
        let next = try #require(Self.bounds(of: "Balance (AUD)", in: document).first)
        #expect(end.midY < words.midY - 4, "the label didn't wrap")
        #expect(words.maxX < value.minX)
        #expect(next.maxY <= end.minY, "the next line overlaps the wrapped label")
    }

    // MARK: Footer and page breaks

    /// Quotes, invoices and receipts all end every page the same way: the business and document on
    /// the left, "Page 2 of 3" on the right, in the bottom margin below the last line.
    @Test func everyPageOfEveryDocumentHasTheSameFooter() throws {
        var receipted = Sample.invoice(.standalone)
        receipted.payments = [Payment(date: Sample.today, amount: Money(dollars: 100))]
        let documents: [(DocumentContent, String)] = [
            (.quote(Sample.quote(extraLines: 40), client: Sample.client, brand: Sample.brand), "Quote Q-0001"),
            (.invoice(Sample.invoice(.standalone), client: Sample.client, brand: Sample.brand, quoteNumber: nil), "Invoice INV-0001"),
            (.receipt(receipted, client: Sample.client, brand: Sample.brand), "Receipt INV-0001"),
        ]
        var footerLines: Set<CGFloat> = []
        for (content, name) in documents {
            let document = Sample.pdf(content)
            for index in 0..<document.pageCount {
                let page = try #require(document.page(at: index))
                let label = "Page \(index + 1) of \(document.pageCount)"
                let footer = try #require(Self.bounds(of: label, in: document, page: index).first, "\(name): \(label)")
                #expect(footer.maxY < PageWriter.margin, "\(name) page \(index + 1): the footer is above the margin")
                #expect(abs(footer.maxX - (PageWriter.pageSize.width - PageWriter.margin)) < 1)
                let left = try #require(Self.bounds(of: name, in: document, page: index).last)
                #expect(abs(left.midY - footer.midY) < 1, "\(name) page \(index + 1)")
                #expect(page.string?.contains("Sample Studio") == true)
                footerLines.insert((footer.minY * 4).rounded() / 4)
                // Nothing else reaches into the bottom margin.
                let low = page.selection(for: CGRect(x: 0, y: footer.maxY + 1, width: PageWriter.pageSize.width,
                                                     height: PageWriter.margin - footer.maxY - 1))?.string ?? ""
                #expect(low.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(name) page \(index + 1): \(low)")
            }
        }
        #expect(footerLines.count == 1, "footers at \(footerLines)")
    }

    // MARK: The logo

    /// A made-up logo: a solid magenta PNG of `width` x `height` pixels.
    static func logo(width: Int, height: Int) throws -> Logo {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("logo-\(UUID().uuidString).png")
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            NSColor(srgbRed: 0.85, green: 0, blue: 0.85, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        // Left in the temporary folder: a bitmap logo reads its file when it's drawn.
        try png.write(to: url)
        return try #require(Logo(url: url))
    }

    /// Where the logo's magenta is on page 1, in points from the top left.
    static func logoBox(_ data: Data) throws -> CGRect {
        let page = try #require(Ink(page: 0, of: data, scale: 2))
        var box = CGRect.null
        for y in 0..<page.image.pixelsHigh / 4 {
            for x in 0..<page.image.pixelsWide / 2 {
                guard let c = page.image.colorAt(x: x, y: y), c.redComponent > 0.7, c.greenComponent < 0.3, c.blueComponent > 0.7
                else { continue }
                box = box.union(CGRect(x: CGFloat(x) / 2, y: CGFloat(y) / 2, width: 0.5, height: 0.5))
            }
        }
        return box
    }

    /// Wide or tall, the logo starts at the top margin and the business name starts 12 pt under the
    /// logo as drawn, not under the room it was allowed.
    @Test func theNameFollowsTheLogoAsDrawn() throws {
        let content = DocumentContent.quote(Sample.quote(), client: Sample.client, brand: Sample.brand)
        for (width, height, drawnWidth, drawnHeight) in [(640, 110, 180.0, 180.0 * 110 / 640), (120, 320, 56.0 * 120 / 320, 56.0)] {
            let data = DocumentRenderer.render(content, style: PDFStyle(logo: try Self.logo(width: width, height: height)))
            let box = try Self.logoBox(data)
            #expect(abs(box.minY - PageWriter.margin) < 1, "\(width) x \(height): top at \(box.minY)")
            #expect(abs(box.minX - PageWriter.margin) < 1)
            #expect(abs(box.width - drawnWidth) < 1.5, "\(width) x \(height): \(box.width) wide")
            #expect(abs(box.height - drawnHeight) < 1.5, "\(width) x \(height): \(box.height) high")
            // The name's top, measured down from the top of the page.
            let document = try #require(PDFDocument(data: data))
            let name = try #require(Self.bounds(of: "Sample Studio", in: document).first)
            let nameTop = PageWriter.pageSize.height - name.maxY
            #expect(nameTop - box.maxY > 8 && nameTop - box.maxY < 16, "\(width) x \(height): name \(nameTop - box.maxY) under the logo")
        }
    }

    /// Right-aligned figures sit on the same baseline as the words on their row, and the table's
    /// column labels on one baseline. Measured in ink: the lowest dark pixel of letters and figures
    /// without descenders, drawn at 8 pixels a point.
    @Test func figuresShareTheBaselineOfTheirRow() throws {
        let data = DocumentRenderer.render(.invoice(Sample.invoice(.standalone), client: Sample.client,
                                                    brand: Sample.brand, quoteNumber: nil), style: PDFStyle())
        let document = try #require(PDFDocument(data: data))
        let page = try #require(Ink(page: 0, of: data, scale: 8))

        let build = try #require(Self.bounds(of: "Build", in: document).first)
        let amount = try #require(Self.bounds(of: "$1,000.00", in: document).last { abs($0.midY - build.midY) < 3 })
        // "Build" against the amount's last "00".
        let buildBase = try #require(page.lowestInk(in: build))
        let amountBase = try #require(page.lowestInk(in: amount.divided(atDistance: amount.width * 0.75, from: .minXEdge).remainder))
        #expect(buildBase == amountBase, "Build at \(buildBase), its amount at \(amountBase)")

        // "De" of "Description" against "Rate"; neither has a descender.
        let description = try #require(Self.bounds(of: "Description", in: document).first)
        let labelBase = try #require(page.lowestInk(in: description.divided(atDistance: description.width * 0.2, from: .minXEdge).slice))
        let rate = try #require(Self.bounds(of: "Rate", in: document).first { abs($0.midY - description.midY) < 3 })
        #expect(page.lowestInk(in: rate) == labelBase)
    }
}

/// A page drawn at `scale` pixels a point, for finding where ink is.
struct Ink {
    let image: NSBitmapImageRep
    let scale: CGFloat

    init?(page index: Int, of pdf: Data, scale: CGFloat) {
        guard let document = PDFDocument(data: pdf), let page = document.page(at: index) else { return nil }
        let box = page.bounds(for: .mediaBox)
        guard let context = CGContext(data: nil, width: Int(box.width * scale), height: Int(box.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        guard let cgImage = context.makeImage() else { return nil }
        image = NSBitmapImageRep(cgImage: cgImage)
        self.scale = scale
    }

    /// The colour at a point in PDF coordinates (origin bottom left).
    func color(at point: CGPoint) -> NSColor? {
        image.colorAt(x: Int(point.x * scale), y: image.pixelsHigh - 1 - Int(point.y * scale))?.usingColorSpace(.sRGB)
    }

    /// The lowest dark point inside `rect` (PDF coordinates), in points from the bottom of the
    /// page; nil when it has no ink.
    func lowestInk(in rect: CGRect) -> CGFloat? {
        let x0 = Int(rect.minX * scale), x1 = Int(rect.maxX * scale)
        let rows = (image.pixelsHigh - Int(rect.maxY * scale))..<(image.pixelsHigh - Int(rect.minY * scale))
        for row in rows.reversed() {
            for x in x0..<x1 where (image.colorAt(x: x, y: row)?.brightnessComponent ?? 1) < 0.6 {
                return CGFloat(image.pixelsHigh - row) / scale
            }
        }
        return nil
    }
}
