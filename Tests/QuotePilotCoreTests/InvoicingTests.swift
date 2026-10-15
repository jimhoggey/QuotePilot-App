import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct InvoicingTests {
    let today = Fixture.today

    @Test func fiftyFiftyDraftsADepositThenTheBalance() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(deposit.kind == .deposit)
        #expect(deposit.number == "INV-0001")
        #expect(deposit.lines.map(\.title) == ["Discovery", "Build"])
        #expect(deposit.lines.allSatisfy { $0.decision == nil })
        #expect(deposit.amount == Money(dollars: 540))
        #expect(deposit.due == today.adding(days: 14))
        #expect(library.activity.first?.message == "Drafted deposit invoice INV-0001 for $540.00 from quote Q-0001")

        let closing = try library.draftNextInvoice(forQuote: id, on: today.adding(days: 20))
        #expect(closing.kind == .final)
        #expect(closing.deductions == [Deduction(label: "Less deposit", invoiceNumber: "INV-0001", amount: Money(dollars: 540))])
        #expect(closing.amount == Money(dollars: 540))
        #expect(library.invoicedAmount(forQuote: id) == Money(dollars: 1080))
        #expect(throws: LibraryError.nothingLeftToInvoice) { try library.draftNextInvoice(forQuote: id, on: today) }
    }

    @Test func oddCentsSplitAddsUpExactly() throws {
        var (library, id) = Fixture.libraryWithQuote()
        var quote = library.quote(id)!
        quote.lines[1].rate = Money(cents: 99_921)   // accepted: $80 + $999.21 = $1,079.21
        try library.update(quote)
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01", "02"], declined: ["03"]), forQuote: id)
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        let closing = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(deposit.amount == Money(cents: 53_961))   // 53,960.5 rounds up
        #expect(closing.amount == Money(cents: 53_960))
        #expect(deposit.amount + closing.amount == Money(cents: 107_921))
    }

    @Test func fullAmountIsInvoicedOnceAtCompletion() throws {
        var (library, id) = Fixture.acceptedLibrary(plan: .fullAmount)
        let invoice = try library.completeJob(quote: id, on: today)
        #expect(invoice?.kind == .full)
        #expect(invoice?.amount == Money(dollars: 1080))
        #expect(library.quote(id)!.completedOn == today)
        let again = try library.completeJob(quote: id, on: today)
        #expect(again == nil)
        #expect(library.nextInvoiceKind(forQuote: id) == nil)
    }

    @Test func completingAFiftyFiftyJobWithoutADepositBillsEverything() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let closing = try library.completeJob(quote: id, on: today)
        #expect(closing?.kind == .final)
        #expect(closing?.deductions == [])
        #expect(closing?.amount == Money(dollars: 1080))
    }

    @Test func completingAfterTheDepositBillsTheBalance() throws {
        var (library, id) = Fixture.acceptedLibrary()
        try library.draftNextInvoice(forQuote: id, on: today)
        let closing = try library.completeJob(quote: id, on: today)
        #expect(closing?.amount == Money(dollars: 540))
    }

    @Test func onlyAcceptedQuotesCanBeInvoiced() {
        var (library, id) = Fixture.libraryWithQuote()
        #expect(throws: LibraryError.notAccepted) { try library.draftNextInvoice(forQuote: id, on: today) }
        #expect(library.nextInvoiceKind(forQuote: id) == nil)
    }

    @Test func acceptanceCantChangeOnceInvoiced() throws {
        var (library, id) = Fixture.acceptedLibrary()
        try library.draftNextInvoice(forQuote: id, on: today)
        #expect(throws: LibraryError.alreadyInvoiced) {
            try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01"], declined: ["02", "03"]), forQuote: id)
        }
    }

    @Test func aVoidedDepositCanBeDraftedAgain() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        try library.voidInvoice(deposit.id)
        #expect(library.invoice(deposit.id)!.status(on: today) == .void)
        #expect(library.nextInvoiceKind(forQuote: id) == .deposit)
        let again = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(again.number == "INV-0002")
    }

    @Test func overdueStartsTheDayAfterDue() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(library.invoice(deposit.id)!.status(on: today) == .draft)
        try library.markSent(invoice: deposit.id)
        let sent = library.invoice(deposit.id)!
        #expect(sent.status(on: sent.due) == .sent)
        #expect(sent.status(on: sent.due.adding(days: 1)) == .overdue(daysLate: 1))
        #expect(InvoiceStatus.overdue(daysLate: 1).label == "Overdue, 1 day")
        #expect(InvoiceStatus.overdue(daysLate: 5).label == "Overdue, 5 days")
    }

    @Test func paymentsMoveAnInvoiceToPartPaidThenPaid() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(throws: LibraryError.notSent) {
            try library.recordPayment(Payment(date: today, amount: Money(dollars: 100)), toInvoice: deposit.id)
        }
        try library.markSent(invoice: deposit.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 200)), toInvoice: deposit.id)
        #expect(library.invoice(deposit.id)!.status(on: today) == .partPaid)
        #expect(library.activity.first?.message == "Recorded $200.00 paid on 15 October 2026 by bank transfer for INV-0001")
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 340), method: .cash), toInvoice: deposit.id)
        #expect(library.invoice(deposit.id)!.status(on: today.adding(days: 60)) == .paid)
        #expect(throws: LibraryError.hasPayments) { try library.voidInvoice(deposit.id) }
    }

    @Test func removingAPaymentUndoesIt() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        let payment = Payment(date: today, amount: Money(dollars: 540))
        try library.recordPayment(payment, toInvoice: deposit.id)
        try library.removePayment(payment.id, fromInvoice: deposit.id)
        #expect(library.invoice(deposit.id)!.owing == Money(dollars: 540))
        #expect(library.activity.first?.message == "Removed the $540.00 payment of 15 October 2026 from INV-0001")
    }

    @Test func duplicatingAnInvoiceMakesAFreshDraft() throws {
        var library = Library()
        var monthly = library.newInvoice(on: today)
        monthly.lines = [LineItem(title: "Hosting and upkeep, October", rate: Money(dollars: 30))]
        try library.update(monthly)
        try library.markSent(invoice: monthly.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 30)), toInvoice: monthly.id)
        let next = try library.duplicateInvoice(monthly.id, on: today.adding(days: 31))
        #expect(next.number == "INV-0002")
        #expect(next.stage == .draft)
        #expect(next.payments.isEmpty)
        #expect(next.issued == today.adding(days: 31))
        #expect(next.lines.map(\.title) == ["Hosting and upkeep, October"])
        #expect(next.lines[0].id != monthly.lines[0].id)
    }

    @Test func duplicatingAQuoteClearsTheClientsDecisions() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let copy = try library.duplicateQuote(id, on: today)
        #expect(copy.number == "Q-0002")
        #expect(copy.stage == .draft)
        #expect(copy.acceptance == nil)
        #expect(copy.lines.allSatisfy { $0.decision == nil })
        #expect(copy.lineCodes == ["01", "02", "03"])
    }
}
