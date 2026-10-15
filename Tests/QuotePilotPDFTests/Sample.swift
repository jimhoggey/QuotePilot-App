import Foundation
import PDFKit
import QuotePilotCore
@testable import QuotePilotPDF

/// Made-up documents for the PDF tests. Never real clients: this repo is public.
enum Sample {
    static let today = Day(year: 2026, month: 10, day: 15)

    static var brand: Brand {
        var brand = Brand()
        brand.businessName = "Sample Studio"
        brand.details = "hello@example.com\n0400 000 000"
        brand.paymentDetails = "BSB 000-000, account 00000000"
        brand.abn = "00 000 000 000"
        return brand
    }

    static let client = Client(name: "Sample Client Pty Ltd", contactName: "Sam Example",
                               email: "sam@example.com", address: "1 Example St")

    /// Q-0001: 01 Discovery (2 hrs × $40), 02 Build ($1,000), 03 Extra screens ($420), plus any
    /// number of long extra lines ("Item 004", "Item 005", …).
    static func quote(extraLines: Int = 0) -> Quote {
        var quote = Quote(number: "Q-0001", clientID: client.id, title: "Booking app, phase 1",
                          issued: today, validUntil: today.adding(days: 30))
        quote.summary = "What's included:\n- A walkthrough of the current process\n- The agreed screens"
        quote.terms = "Prices are fixed for the work listed."
        quote.addLine(LineItem(title: "Discovery", detail: "Walkthrough of the current process",
                               quantity: 2, unit: .hours, rate: Money(dollars: 40)))
        quote.addLine(LineItem(title: "Build", rate: Money(dollars: 1000)))
        quote.addLine(LineItem(title: "Extra screens", rate: Money(dollars: 420)))
        for n in 0..<extraLines {
            quote.addLine(LineItem(title: "Item " + String(format: "%03d", n + 4),
                                   detail: String(repeating: "A longer description that wraps onto more lines. ", count: 3),
                                   rate: Money(dollars: 10)))
        }
        return quote
    }

    static func invoice(_ kind: InvoiceKind, taxed: Bool = false) -> Invoice {
        Invoice(number: "INV-0001", clientID: client.id, kind: kind, issued: today, due: today.adding(days: 14),
                taxed: taxed, lines: Array(quote().lines.prefix(2)), stage: .sent)
    }

    static func pdf(_ content: DocumentContent, style: PDFStyle = PDFStyle()) -> PDFDocument {
        PDFDocument(data: DocumentRenderer.render(content, style: style))!
    }

    static func text(_ document: PDFDocument) -> String {
        (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
    }
}
