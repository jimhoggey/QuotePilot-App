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
