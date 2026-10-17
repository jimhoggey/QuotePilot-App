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

    @Test func aDepositTheFinalDeductsCantBeVoided() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        try library.draftNextInvoice(forQuote: id, on: today)
        #expect(throws: LibraryError.deductedByFinal("INV-0002")) { try library.voidInvoice(deposit.id) }
        #expect(library.invoice(deposit.id)!.stage == .sent)
    }

    @Test func aDraftDepositTheFinalDeductsCantBeDeleted() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.draftNextInvoice(forQuote: id, on: today)
        #expect(throws: LibraryError.deductedByFinal("INV-0002")) { try library.deleteDraft(invoice: deposit.id) }
        #expect(library.invoice(deposit.id) != nil)
    }

    @Test func aDepositKnowsWhichFinalInvoiceDeductsIt() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(library.finalDeducting(deposit.id) == nil)
        let final = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(library.finalDeducting(deposit.id)?.id == final.id)
        #expect(library.finalDeducting(deposit.id)?.number == "INV-0002")
        // Only a deposit is deducted; an unknown invoice is nobody's.
        #expect(library.finalDeducting(final.id) == nil)
        #expect(library.finalDeducting(UUID()) == nil)
        // A final that is void deducts nothing.
        try library.markSent(invoice: final.id)
        try library.voidInvoice(final.id)
        #expect(library.finalDeducting(deposit.id) == nil)
    }

    @Test func aQuoteKnowsItsClosingInvoice() throws {
        var (library, id) = Fixture.acceptedLibrary()
        #expect(library.closingInvoice(forQuote: id) == nil)
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(library.closingInvoice(forQuote: id) == nil, "a deposit doesn't close the quote")
        let final = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(library.closingInvoice(forQuote: id)?.id == final.id)
        #expect(library.closingInvoice(forQuote: UUID()) == nil)
        try library.markSent(invoice: final.id)
        try library.voidInvoice(final.id)
        #expect(library.closingInvoice(forQuote: id) == nil, "a void closing invoice no longer counts")
        #expect(library.invoice(deposit.id) != nil)

        var (fullLibrary, fullID) = Fixture.acceptedLibrary(plan: .fullAmount)
        let full = try fullLibrary.draftNextInvoice(forQuote: fullID, on: today)
        #expect(fullLibrary.closingInvoice(forQuote: fullID)?.id == full.id)
        #expect(full.kind == .full)
    }

    @Test func onceTheFinalIsGoneTheDepositCanBeVoided() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        let closing = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: closing.id)
        try library.voidInvoice(closing.id)
        try library.voidInvoice(deposit.id)
        #expect(library.invoice(deposit.id)!.stage == .void)
        #expect(library.nextInvoiceKind(forQuote: id) == .deposit)
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
        var original = try #require(library.quote(id))
        original.included = ["Design"]
        original.notIncluded = ["Printing"]
        try library.update(original)
        let copy = try library.duplicateQuote(id, on: today)
        #expect(copy.included == ["Design"])
        #expect(copy.notIncluded == ["Printing"])
        #expect(copy.number == "Q-0002")
        #expect(copy.stage == .draft)
        #expect(copy.acceptance == nil)
        #expect(copy.lines.allSatisfy { $0.decision == nil })
        #expect(copy.lineCodes == ["01", "02", "03"])
    }
}
