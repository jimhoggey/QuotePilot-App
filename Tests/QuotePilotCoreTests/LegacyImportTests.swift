import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct LegacyImportTests {
    let today = Day(year: 2026, month: 10, day: 15)

    /// Made-up backup in the old tool's format.
    let backup = Data(#"""
    {
      "app": "invoice-quote-maker",
      "settings": { "logo": "data:image/png;base64,iVBORw0KGgo=", "logoHeight": 56, "accent": "#0B6B66", "paper": "A4" },
      "docs": {
        "a1": { "id": "a1", "type": "quote", "number": "Q-0001", "issued": "2026-10-04", "due": "2026-11-03",
                "reference": "Booking app, phase 1",
                "from": { "name": "Sample Studio", "details": "hello@example.com" },
                "to": { "name": "Sample Client Pty Ltd", "details": "1 Example St\nExampleton" },
                "items": [ { "title": "Discovery", "detail": "Walkthrough", "qty": 2, "unit": "hr", "rate": 40 },
                           { "title": "Build (50% deposit)", "detail": "", "qty": 1, "unit": "unit", "rate": 750 } ],
                "tax": { "mode": "none", "rate": 10, "label": "GST" }, "discount": { "value": 0, "kind": "pct" },
                "paid": 0, "summary": "- Walkthrough\n- Scope", "payment": "PayID: hello@example.com",
                "notes": "Quote terms" },
        "b2": { "id": "b2", "type": "invoice", "number": "INV-0001", "issued": "2026-10-06", "due": "2026-10-20",
                "reference": "", "from": { "name": "Sample Studio", "details": "" },
                "to": { "name": "sample client pty ltd", "details": "" },
                "items": [ { "title": "Hosting, October", "detail": "", "qty": 1, "unit": "unit", "rate": 30 } ],
                "tax": { "mode": "none", "rate": 10, "label": "GST" }, "discount": { "value": 5, "kind": "pct" },
                "paid": 10, "summary": "", "payment": "", "notes": "" }
      },
      "currentId": "a1"
    }
    """#.utf8)

    @Test func importsQuotesInvoicesAndClients() throws {
        var library = Library()
        let report = try LegacyImport.importBackup(backup, into: &library, today: today)
        #expect(report.addedQuotes == ["Q-0001"])
        #expect(report.addedInvoices == ["INV-0001"])
        #expect(report.addedClients == ["Sample Client Pty Ltd"])
        #expect(report.notes == ["INV-0001: its discount wasn't imported; add it as a line if needed."])

        let quote = try #require(library.quote(number: "Q-0001"))
        #expect(quote.stage == .sent)
        #expect(quote.title == "Booking app, phase 1")
        #expect(quote.lineCodes == ["01", "02"])
        #expect(quote.lines.map(\.amount) == [Money(dollars: 80), Money(dollars: 750)])
        #expect(quote.lines[0].unit == .hours)
        #expect(quote.summary == "- Walkthrough\n- Scope")
        #expect(quote.nextLineCode() == "03")
        #expect(library.client(quote.clientID)?.address == "1 Example St\nExampleton")

        let invoice = try #require(library.invoices.first)
        #expect(invoice.clientID == quote.clientID)
        #expect(invoice.kind == .standalone)
        #expect(invoice.payments.map(\.amount) == [Money(dollars: 10)])
        #expect(invoice.payments.first?.note == "Imported: already paid")

        #expect(library.brand.businessName == "Sample Studio")
        #expect(library.brand.paymentDetails == "PayID: hello@example.com")
        #expect(report.logoData == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        #expect(library.nextNumber(.quote) == "Q-0002")
        #expect(library.nextNumber(.invoice) == "INV-0002")
        #expect(library.activity.first?.message == "Imported 1 quote and 1 invoice from Invoice Generator.")
    }

    @Test func importingTwiceSkipsWhatsAlreadyThere() throws {
        var library = Library()
        _ = try LegacyImport.importBackup(backup, into: &library, today: today)
        let again = try LegacyImport.importBackup(backup, into: &library, today: today)
        #expect(again.addedQuotes.isEmpty)
        #expect(again.addedInvoices.isEmpty)
        #expect(again.skipped == ["Q-0001", "INV-0001"])
        #expect(library.quotes.count == 1)
        #expect(library.clients.count == 1)
    }

    @Test func anExistingLogoIsKept() throws {
        var library = Library()
        library.brand.logoFile = "logo.png"
        let report = try LegacyImport.importBackup(backup, into: &library, today: today)
        #expect(report.logoData == nil)
    }

    @Test func otherFilesAreRejected() {
        var library = Library()
        #expect(throws: LegacyImportError.notABackup) {
            try LegacyImport.importBackup(Data("[1, 2, 3]".utf8), into: &library, today: today)
        }
    }
}
