import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct ModelTests {
    let today = Day(year: 2026, month: 10, day: 15)

    @Test func unitsDescribeQuantities() {
        #expect(Unit.hours.describe(2) == "2 hrs")
        #expect(Unit.hours.describe(1) == "1 hr")
        #expect(Unit.hours.describe(1.5) == "1.5 hrs")
        #expect(Unit.days.describe(1) == "1 day")
        #expect(Unit.units.describe(3) == "3")
    }

    @Test func lineAmountsAndTotals() {
        let lines = [
            LineItem(title: "Discovery", quantity: 1.5, unit: .hours, rate: Money(dollars: 40)),
            LineItem(title: "Build", rate: Money(dollars: 1000)),
        ]
        #expect(lines[0].amount == Money(dollars: 60))
        #expect(lines.subtotal == Money(dollars: 1060))
        #expect(Totals(subtotal: lines.subtotal, taxed: false).total == Money(dollars: 1060))
        let taxed = Totals(subtotal: lines.subtotal, taxed: true)
        #expect(taxed.gst == Money(dollars: 106))
        #expect(taxed.total == Money(dollars: 1166))
    }

    @Test func emailTemplatesFillPlaceholders() {
        let template = EmailTemplate(subject: "Quote {number}", body: "Hi {contact}, {amount} from {business}")
        let filled = template.filled(["number": "Q-0003", "contact": "Sam", "amount": "$500.00", "business": "Sample Studio"])
        #expect(filled.subject == "Quote Q-0003")
        #expect(filled.body == "Hi Sam, $500.00 from Sample Studio")
    }

    @Test func clientGreetingUsesTheContactsFirstName() {
        #expect(Client(name: "Sample Client Pty Ltd", contactName: "Sam Example").greetingName == "Sam")
        #expect(Client(name: "Sample Client Pty Ltd").greetingName == "Sample Client Pty Ltd")
    }

    @Test func numbersCountUpAndAreNeverReused() throws {
        var library = Library()
        #expect(library.nextNumber(.quote) == "Q-0001")
        #expect(library.nextNumber(.invoice) == "INV-0001")
        _ = library.newQuote(on: today)
        let second = library.newQuote(on: today)
        try library.deleteDraft(quote: second.id)
        #expect(library.nextNumber(.quote) == "Q-0003")
        library.usedNumbers.append("Q-0041")
        #expect(library.nextNumber(.quote) == "Q-0042")
        #expect(library.nextNumber(.invoice) == "INV-0001")
    }

    @Test func newDocumentsTakeTheBrandsDefaults() {
        var library = Library()
        library.brand.quoteValidDays = 30
        library.brand.paymentDueDays = 14
        let quote = library.newQuote(on: today)
        #expect(quote.validUntil == today.adding(days: 30))
        #expect(quote.stage == .draft)
        #expect(quote.terms == library.brand.quoteTerms)
        let invoice = library.newInvoice(on: today)
        #expect(invoice.due == today.adding(days: 14))
        #expect(invoice.kind == .standalone)
        #expect(library.activity.first?.message == "Started invoice INV-0001")
    }

    @Test func invoiceAmounts() {
        var invoice = Invoice(number: "INV-0001", kind: .deposit, issued: today, due: today.adding(days: 14),
                              lines: [LineItem(title: "Build", rate: Money(dollars: 1500))])
        invoice.depositPercent = 50
        #expect(invoice.amount == Money(dollars: 750))

        var closing = Invoice(number: "INV-0002", kind: .final, issued: today, due: today.adding(days: 14),
                              lines: [LineItem(title: "Build", rate: Money(dollars: 1500))])
        closing.deductions = [Deduction(label: "Less deposit", invoiceNumber: "INV-0001", amount: Money(dollars: 750))]
        #expect(closing.amount == Money(dollars: 750))
        closing.payments = [Payment(date: today, amount: Money(dollars: 500))]
        #expect(closing.paid == Money(dollars: 500))
        #expect(closing.owing == Money(dollars: 250))
    }

    @Test func onlyDraftsCanBeDeleted() throws {
        var library = Library()
        let quote = library.newQuote(on: today)
        var sent = quote
        sent.stage = .sent
        try library.update(sent)
        #expect(throws: LibraryError.notDraft) { try library.deleteDraft(quote: quote.id) }
    }

    @Test func libraryRoundTripsThroughJSON() throws {
        var library = Library()
        library.addClient(Client(name: "Sample Client Pty Ltd", email: "accounts@example.com"))
        var quote = library.newQuote(on: today, clientID: library.clients[0].id)
        quote.lines = [LineItem(code: "01", title: "Discovery", quantity: 2, unit: .hours, rate: Money(dollars: 40))]
        try library.update(quote)
        _ = library.newInvoice(on: today)

        let first = try Library.makeEncoder().encode(library)
        let decoded = try Library.makeDecoder().decode(Library.self, from: first)
        let second = try Library.makeEncoder().encode(decoded)
        #expect(first == second)
        #expect(decoded.quotes[0].lines[0].amount == Money(dollars: 80))
    }
}
