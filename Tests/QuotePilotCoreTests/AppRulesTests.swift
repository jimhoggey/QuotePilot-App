import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct AppRulesTests {
    let today = Fixture.today

    /// A sent standalone invoice for $300, with the sample client.
    func sentStandalone(_ library: inout Library) throws -> Invoice {
        var invoice = library.newInvoice(on: today, clientID: library.clients[0].id)
        invoice.lines = [LineItem(title: "Extra work", rate: Money(dollars: 300))]
        try library.update(invoice)
        try library.markSent(invoice: invoice.id)
        return library.invoice(invoice.id)!
    }

    @Test func sentInvoicesCantBeEdited() throws {
        var (library, _) = Fixture.acceptedLibrary()
        var invoice = try sentStandalone(&library)
        invoice.title = "Renamed"
        #expect(throws: LibraryError.notEditable) { try library.update(invoice) }
        #expect(library.invoice(invoice.id)?.title == "")
    }

    @Test func quoteInvoicesKeepTheirQuotesClient() throws {
        var (library, quoteID) = Fixture.acceptedLibrary()
        let other = Client(name: "Example Bakery")
        library.addClient(other)
        let deposit = try library.draftNextInvoice(forQuote: quoteID, on: today)
        var edited = deposit
        edited.clientID = other.id
        edited.title = "Deposit for the booking app"
        try library.update(edited)
        #expect(library.invoice(deposit.id)?.clientID == deposit.clientID)
        #expect(library.invoice(deposit.id)?.title == "Deposit for the booking app")
    }

    @Test func editingADraftNeverChangesItsStageOrMoneyTrail() throws {
        var (library, _) = Fixture.acceptedLibrary()
        var invoice = library.newInvoice(on: today, clientID: library.clients[0].id)
        invoice.lines = [LineItem(title: "Work", rate: Money(dollars: 100))]
        invoice.stage = .sent
        invoice.sentAt = Date()
        invoice.payments = [Payment(date: today, amount: Money(dollars: 5))]
        invoice.kind = .deposit
        try library.update(invoice)
        let stored = try #require(library.invoice(invoice.id))
        #expect(stored.stage == .draft)
        #expect(stored.sentAt == nil)
        #expect(stored.payments.isEmpty)
        #expect(stored.kind == .standalone)
        #expect(stored.lines.map(\.title) == ["Work"])
    }

    @Test func paymentsMustBePositiveAndNotMoreThanOwing() throws {
        var (library, _) = Fixture.acceptedLibrary()
        let invoice = try sentStandalone(&library)
        #expect(throws: LibraryError.paymentNotPositive) {
            try library.recordPayment(Payment(date: today, amount: .zero), toInvoice: invoice.id)
        }
        #expect(throws: LibraryError.paymentNotPositive) {
            try library.recordPayment(Payment(date: today, amount: Money(dollars: -5)), toInvoice: invoice.id)
        }
        #expect(throws: LibraryError.paymentMoreThanOwing(Money(dollars: 300))) {
            try library.recordPayment(Payment(date: today, amount: Money(dollars: 301)), toInvoice: invoice.id)
        }
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 300)), toInvoice: invoice.id)
        #expect(library.invoice(invoice.id)?.owing == .zero)
    }

    @Test func numbersKeptUsedAreNeverIssuedAgain() {
        var library = Library()
        library.keepUsed(["Q-0007", "INV-0003", "Q-0007"])
        #expect(library.usedNumbers == ["Q-0007", "INV-0003"])
        #expect(library.nextNumber(.quote) == "Q-0008")
        #expect(library.nextNumber(.invoice) == "INV-0004")
        // Keeping them twice changes nothing.
        library.keepUsed(["Q-0007"])
        #expect(library.usedNumbers == ["Q-0007", "INV-0003"])
    }

    @Test func theNumbersOnQuotesAndInvoicesCount() throws {
        var (library, id) = Fixture.acceptedLibrary()
        try library.draftNextInvoice(forQuote: id, on: today)
        #expect(library.documentNumbers == ["Q-0001", "INV-0001"])
    }

    @Test func numbersInMailedFileNamesAreFound() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotePilotTests-\(UUID().uuidString)", isDirectory: true)
        let year = root.appendingPathComponent("2026", isDirectory: true)
        try FileManager.default.createDirectory(at: year, withIntermediateDirectories: true)
        for name in ["Q-0003 Sample Client Pty Ltd.pdf", "Q-0003 Sample Client Pty Ltd (2).pdf",
                     "Receipt INV-0009 Sample Client Pty Ltd.pdf", "reply for q-0012 (scan).pdf",
                     "Q-10050 Sample Client Pty Ltd.pdf", "Q-00021.pdf", "XQ-0004.pdf", "Q-1234567.pdf",
                     "Q-12.pdf", "notes.txt"] {
            try Data().write(to: year.appendingPathComponent(name))
        }
        #expect(SentArchive.numbers(in: root) == ["INV-0009", "Q-0003", "Q-0012", "Q-10050"])
        // A folder that doesn't exist has none.
        #expect(SentArchive.numbers(in: root.appendingPathComponent("missing")).isEmpty)
    }

    @Test func receiptsNeedAPayment() throws {
        var (library, _) = Fixture.acceptedLibrary()
        let invoice = try sentStandalone(&library)
        #expect(throws: LibraryError.noPayments) { try library.markReceiptSent(invoice: invoice.id) }
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 100)), toInvoice: invoice.id)
        try library.markReceiptSent(invoice: invoice.id)
        #expect(library.invoice(invoice.id)?.receiptSentAt != nil)
    }

    @Test func acceptanceNeedsASentQuote() {
        var (library, id) = Fixture.libraryWithQuote(stage: .draft)
        #expect(throws: LibraryError.notSent) {
            try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01"], declined: ["02", "03"]), forQuote: id)
        }
        #expect(library.quote(id)?.stage == .draft)
    }

    @Test func completingTwiceChangesNothing() throws {
        var (library, id) = Fixture.acceptedLibrary(plan: .fullAmount)
        try library.completeJob(quote: id, on: today)
        let entries = library.activity.count
        #expect(try library.completeJob(quote: id, on: today.adding(days: 3)) == nil)
        #expect(library.quote(id)?.completedOn == today)
        #expect(library.activity.count == entries)
    }

    @Test func mailDraftsFillTheBrandsWording() throws {
        var (library, quoteID) = Fixture.acceptedLibrary()
        let quote = try #require(library.mailDraft(forQuote: quoteID))
        #expect(quote.to == "sam@example.com")
        #expect(quote.subject == "Quote Q-0001 from Sample Studio")
        #expect(quote.body.hasPrefix("Hi Sam,"))

        let deposit = try library.draftNextInvoice(forQuote: quoteID, on: today)
        let invoice = try #require(library.mailDraft(forInvoice: deposit.id))
        #expect(invoice.subject == "Invoice INV-0001 from Sample Studio")
        #expect(invoice.body.contains("for $540.00, due 29 October 2026"))

        try library.markSent(invoice: deposit.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 540)), toInvoice: deposit.id)
        let receipt = try #require(library.mailDraft(forReceipt: deposit.id))
        #expect(receipt.subject == "Receipt for invoice INV-0001")
        #expect(library.mailDraft(forQuote: UUID()) == nil)
    }

    @Test func nestedTypesTolerateMissingFields() throws {
        let decoder = Library.makeDecoder()
        let payment = try decoder.decode(Payment.self, from: Data(#"""
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","date":"2026-10-15","amount":5000}
            """#.utf8))
        #expect(payment.method == .bankTransfer)
        #expect(payment.note == "")
        let templates = try decoder.decode(EmailTemplates.self, from: Data(#"""
            {"quote":{"subject":"Q {number}","body":"Hi"}}
            """#.utf8))
        #expect(templates.quote.subject == "Q {number}")
        #expect(templates.receipt == EmailTemplates.standard.receipt)
        let entry = try decoder.decode(ActivityEntry.self, from: Data(#"""
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","at":"2026-10-15T01:02:03Z"}
            """#.utf8))
        #expect(entry.number == nil)
        #expect(entry.message == "")
        let acceptance = try decoder.decode(Acceptance.self, from: Data(#"""
            {"recordedAt":"2026-10-15T01:02:03Z","source":"byHand"}
            """#.utf8))
        #expect(acceptance.accepted.isEmpty)
        #expect(acceptance.clientName == "")
    }

    @Test func theArchivePicksAFreshNameEachTime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QuotePilotArchive-\(UUID().uuidString)")
        let first = SentArchive.freshURL(for: "Q-0001 Sample Client Pty Ltd.pdf", year: 2026, in: root)
        #expect(first.path.hasSuffix("/2026/Q-0001 Sample Client Pty Ltd.pdf"))
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: first)
        let second = SentArchive.freshURL(for: "Q-0001 Sample Client Pty Ltd.pdf", year: 2026, in: root)
        #expect(second.lastPathComponent == "Q-0001 Sample Client Pty Ltd (2).pdf")
    }

    @Test func theTaxExportNeverStartsAFieldWithAFormula() {
        #expect(csvText("=SUM(A1)") == "'=SUM(A1)")
        #expect(csvText("+61 400") == "'+61 400")
        #expect(csvText("@home, office") == "\"'@home, office\"")
        #expect(csvText("Sample Client") == "Sample Client")
    }
}
