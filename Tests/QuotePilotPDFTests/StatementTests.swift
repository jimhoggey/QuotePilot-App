import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotPDF

/// A statement: the invoices a client still owes, what each has had paid, and the total owing.
@Suite struct StatementTests {
    let today = Sample.today

    /// Sample Client: INV-0001 $500, 30 days late, $200 paid; INV-0002 $300 not due yet; INV-0003 a
    /// $100 draft; INV-0004 $50 paid in full. Other Client: INV-0005 $80 owing. Quiet Client: nothing.
    func library() throws -> Library {
        var library = Library(brand: Sample.brand)
        library.addClient(Sample.client)
        library.addClient(Client(name: "Other Client"))
        library.addClient(Client(name: "Quiet Client"))
        func invoice(_ dollars: Int, issued: Day, client: Int, sent: Bool = true, paid: Int = 0) throws {
            var invoice = library.newInvoice(on: issued, clientID: library.clients[client].id)
            invoice.lines = [LineItem(title: "Work", rate: Money(dollars: dollars))]
            try library.update(invoice)
            if sent { try library.markSent(invoice: invoice.id) }
            if paid > 0 { try library.recordPayment(Payment(date: today, amount: Money(dollars: paid)), toInvoice: invoice.id) }
        }
        try invoice(500, issued: today.adding(days: -44), client: 0, paid: 200)
        try invoice(300, issued: today.adding(days: -5), client: 0)
        try invoice(100, issued: today, client: 0, sent: false)
        try invoice(50, issued: today, client: 0, paid: 50)
        try invoice(80, issued: today, client: 1)
        return library
    }

    @Test func itListsOnlyTheClientsSentInvoicesStillOwingOldestFirst() throws {
        let library = try library()
        #expect(library.owingInvoices(forClient: library.clients[0].id).map(\.number) == ["INV-0001", "INV-0002"])
        #expect(library.owingInvoices(forClient: library.clients[2].id).isEmpty)
    }

    @Test func theEmailListsWhatsOwingAndTheTotal() throws {
        let library = try library()
        let draft = try #require(library.mailDraft(forStatement: library.clients[0].id))
        #expect(draft.subject == "Statement from Sample Studio")
        #expect(draft.body.contains("• INV-0001, $300.00 owing, due "))
        #expect(draft.body.contains("• INV-0002, $300.00 owing, due "))
        #expect(draft.body.contains("Total owing: $600.00."))
        #expect(library.mailDraft(forStatement: library.clients[2].id) == nil, "nothing owing, nothing to send")
    }

    @Test func thePDFShowsEachInvoiceAndTheTotalOwing() throws {
        let library = try library()
        let client = library.clients[0]
        let content = DocumentContent.statement(library.owingInvoices(forClient: client.id), client: client,
                                                brand: library.brand, on: today)
        #expect(content.title == "Statement" && content.amount == "$600.00" && content.amountNote == "1 overdue")
        #expect(content.columns == DocumentContent.Columns(description: "Invoice", quantity: "Total", rate: "Paid", amount: "Owing"))
        #expect(content.rows.map(\.rate) == ["$200.00", "$0.00"])
        #expect(content.rows[0].detail.hasSuffix(", overdue") && !content.rows[1].detail.hasSuffix(", overdue"))
        #expect(content.fileName == "Statement 2026-10-15 Sample Client Pty Ltd.pdf")
        let pdf = Sample.pdf(content)
        _ = Picture(page1: try #require(pdf.dataRepresentation()), name: "statement")
        let text = Sample.text(pdf)
        for words in ["Statement", "Owing", "Paid", "INV-0001", "Total owing", "BSB 000-000"] {
            #expect(text.contains(words), "\(words)")
        }
    }

    /// Libraries from before statements get the standard wording for the email.
    @Test func anOlderLibraryGetsTheStandardWording() throws {
        let old = #"{"quote":{"subject":"Q","body":"B"},"invoice":{"subject":"I","body":"B"},"receipt":{"subject":"R","body":"B"}}"#
        let templates = try JSONDecoder().decode(EmailTemplates.self, from: Data(old.utf8))
        #expect(templates.statement == EmailTemplates.standard.statement)
    }
}
