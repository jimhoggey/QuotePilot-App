import Foundation
import Testing
@testable import QuotePilotCore

/// Once a quote has invoices, nothing that changes what is billed may change underneath them.
@Suite struct MoneyIntegrityTests {
    let today = Fixture.today

    /// 50/50, 01 and 02 accepted ($1,080), the $540 deposit INV-0001 drafted.
    func withDeposit() throws -> (library: Library, quoteID: UUID, deposit: Invoice) {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        return (library, id, deposit)
    }

    /// Applies `change` to the quote and expects the library to refuse it, leaving the quote as it was.
    func expectQuoteRefused(_ library: Library, _ id: UUID, _ change: (inout Quote) -> Void,
                            sourceLocation: SourceLocation = #_sourceLocation) {
        var library = library
        let before = library.quote(id)!
        var quote = before
        change(&quote)
        #expect(throws: LibraryError.alreadyInvoiced, sourceLocation: sourceLocation) { try library.update(quote) }
        #expect(library.quote(id) == before, sourceLocation: sourceLocation)
    }

    // MARK: Quotes with invoices

    @Test func switchingToFullAmountAfterADepositIsRefused() throws {
        var (library, id, _) = try withDeposit()
        expectQuoteRefused(library, id) { $0.plan = .fullAmount }
        // So Job complete still bills only the balance: $540 + $540, never $540 + $1,080.
        let closing = try library.completeJob(quote: id, on: today)
        #expect(closing?.kind == .final)
        #expect(closing?.amount == Money(dollars: 540))
        #expect(library.invoicedAmount(forQuote: id) == Money(dollars: 1080))
    }

    @Test func switchingToFiftyFiftyAfterAFullInvoiceIsRefused() throws {
        var (library, id) = Fixture.acceptedLibrary(plan: .fullAmount)
        try library.draftNextInvoice(forQuote: id, on: today)
        expectQuoteRefused(library, id) { $0.plan = .fiftyFifty }
        #expect(library.nextInvoiceKind(forQuote: id) == nil)
    }

    @Test func changingTheTaxSettingAfterInvoicingIsRefused() throws {
        let (library, id, _) = try withDeposit()
        expectQuoteRefused(library, id) { $0.taxed = true }
    }

    @Test func changingWhatALineBillsAfterInvoicingIsRefused() throws {
        let (library, id, _) = try withDeposit()
        expectQuoteRefused(library, id) { $0.lines[1].rate = Money(dollars: 1200) }
        expectQuoteRefused(library, id) { $0.lines[0].quantity = 3 }
        expectQuoteRefused(library, id) { $0.lines[0].unit = .days }
        expectQuoteRefused(library, id) { $0.lines[2].decision = .accepted }
        expectQuoteRefused(library, id) { $0.lines[1].code = "09" }
    }

    @Test func addingOrRemovingALineAfterInvoicingIsRefused() throws {
        let (library, id, _) = try withDeposit()
        expectQuoteRefused(library, id) { $0.addLine(LineItem(title: "Training", rate: Money(dollars: 200))) }
        expectQuoteRefused(library, id) { $0.lines.remove(at: 2) }
        expectQuoteRefused(library, id) { $0.lines[2] = LineItem(title: "Extra screens", rate: Money(dollars: 420)) }
    }

    @Test func wordingAndDatesStayEditableAfterInvoicing() throws {
        var (library, id, _) = try withDeposit()
        var quote = library.quote(id)!
        quote.title = "Booking app, phase 1 (revised wording)"
        quote.summary = "A new summary."
        quote.terms = "New terms."
        quote.validUntil = quote.validUntil.adding(days: 30)
        quote.lines[0].title = "Discovery workshop"
        quote.lines[0].detail = "Two hours with the team"
        quote.lines.swapAt(0, 1)
        try library.update(quote)
        #expect(library.quote(id) == quote)
        #expect(library.quote(id)!.acceptedTotals.total == Money(dollars: 1080))
    }

    @Test func aQuoteWithNoInvoicesCanStillChangeItsPlanAndLines() throws {
        var (library, id) = Fixture.acceptedLibrary()
        var quote = library.quote(id)!
        quote.plan = .fullAmount
        quote.lines[1].rate = Money(dollars: 1200)
        try library.update(quote)
        #expect(library.quote(id)!.plan == .fullAmount)
    }

    @Test func voidedInvoicesDontLockTheQuote() throws {
        var (library, id, deposit) = try withDeposit()
        try library.markSent(invoice: deposit.id)
        try library.voidInvoice(deposit.id)
        var quote = library.quote(id)!
        quote.plan = .fullAmount
        try library.update(quote)
        #expect(library.nextInvoiceKind(forQuote: id) == .full)
    }

    // MARK: Deposits a final invoice deducts

    /// Applies `change` to the invoice and expects the library to refuse it, leaving the invoice as it was.
    func expectInvoiceRefused(_ library: Library, _ invoiceID: UUID, final: String, _ change: (inout Invoice) -> Void,
                              sourceLocation: SourceLocation = #_sourceLocation) {
        var library = library
        let before = library.invoice(invoiceID)!
        var invoice = before
        change(&invoice)
        #expect(throws: LibraryError.deductedByFinal(final), sourceLocation: sourceLocation) { try library.update(invoice) }
        #expect(library.invoice(invoiceID) == before, sourceLocation: sourceLocation)
    }

    @Test func aDepositTheFinalDeductsCantBeEditedInWhatItBills() throws {
        var (library, id, deposit) = try withDeposit()
        let final = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(final.number == "INV-0002")
        expectInvoiceRefused(library, deposit.id, final: "INV-0002") { $0.lines[0].rate = Money(dollars: 100) }
        expectInvoiceRefused(library, deposit.id, final: "INV-0002") { $0.lines.removeLast() }
        expectInvoiceRefused(library, deposit.id, final: "INV-0002") { $0.taxed = true }
        expectInvoiceRefused(library, deposit.id, final: "INV-0002") { $0.depositPercent = 60 }
        expectInvoiceRefused(library, deposit.id, final: "INV-0002") { $0.number = "INV-0009" }
        expectInvoiceRefused(library, deposit.id, final: "INV-0002") { $0.stage = .void }
        // The final still deducts exactly what the deposit bills.
        #expect(library.invoice(final.id)!.amount == Money(dollars: 540))
    }

    @Test func aDeductedDepositKeepsItsWordingAndDatesEditable() throws {
        var (library, id, deposit) = try withDeposit()
        try library.draftNextInvoice(forQuote: id, on: today)
        var edited = library.invoice(deposit.id)!
        edited.title = "Booking app, deposit"
        edited.terms = "New terms."
        edited.due = edited.due.adding(days: 7)
        try library.update(edited)
        #expect(library.invoice(deposit.id) == edited)
    }

    @Test func aDepositNoFinalDeductsCanStillBeEdited() throws {
        var (library, _, deposit) = try withDeposit()
        var edited = deposit
        edited.lines[0].rate = Money(dollars: 50)
        try library.update(edited)
        #expect(library.invoice(deposit.id)!.amount == Money(dollars: 550))
    }

    @Test func onceTheFinalIsVoidTheDepositCanBeEditedAgain() throws {
        var (library, id, deposit) = try withDeposit()
        let final = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: final.id)
        try library.voidInvoice(final.id)
        var edited = library.invoice(deposit.id)!
        edited.lines[0].rate = Money(dollars: 50)
        try library.update(edited)
        #expect(library.invoice(deposit.id)!.amount == Money(dollars: 550))
    }

    // MARK: Defence in depth: one closing invoice, whatever the plan says

    @Test func nextInvoiceKindIsNilOnceAFullInvoiceExists() throws {
        var (library, id) = Fixture.acceptedLibrary(plan: .fullAmount)
        try library.draftNextInvoice(forQuote: id, on: today)
        library.quotes[0].plan = .fiftyFifty   // set behind update(_:)'s back
        #expect(library.nextInvoiceKind(forQuote: id) == nil)
        #expect(throws: LibraryError.nothingLeftToInvoice) { try library.draftNextInvoice(forQuote: id, on: today) }
    }

    @Test func nextInvoiceKindIsNilOnceAFinalInvoiceExists() throws {
        var (library, id) = Fixture.acceptedLibrary()
        try library.completeJob(quote: id, on: today)   // 50/50 with no deposit: a final bills everything
        library.quotes[0].plan = .fullAmount
        #expect(library.nextInvoiceKind(forQuote: id) == nil)
    }

    @Test func completingTheJobDraftsNothingMoreOnceAClosingInvoiceExists() throws {
        var (library, id) = Fixture.acceptedLibrary(plan: .fullAmount)
        try library.draftNextInvoice(forQuote: id, on: today)
        library.quotes[0].plan = .fiftyFifty
        #expect(try library.completeJob(quote: id, on: today) == nil)
        #expect(library.invoices(forQuote: id).count == 1)
        #expect(library.invoicedAmount(forQuote: id) == Money(dollars: 1080))
    }

    @Test func aVoidClosingInvoiceDoesntCount() throws {
        var (library, id) = Fixture.acceptedLibrary(plan: .fullAmount)
        let full = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: full.id)
        try library.voidInvoice(full.id)
        #expect(library.nextInvoiceKind(forQuote: id) == .full)
    }

    @Test func aClosingInvoiceDeductsALiveDepositWhateverThePlan() throws {
        var (library, id, _) = try withDeposit()
        library.quotes[0].plan = .fullAmount   // set behind update(_:)'s back
        let closing = try #require(try library.completeJob(quote: id, on: today))
        #expect(closing.kind == .full)
        #expect(closing.deductions == [Deduction(label: "Less deposit", invoiceNumber: "INV-0001", amount: Money(dollars: 540))])
        #expect(closing.amount == Money(dollars: 540))
        #expect(library.invoicedAmount(forQuote: id) == Money(dollars: 1080))
    }

    @Test func aDepositAFullInvoiceDeductsCantBeVoidedOrDeleted() throws {
        var (library, id, deposit) = try withDeposit()
        library.quotes[0].plan = .fullAmount
        let full = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(full.kind == .full)
        #expect(throws: LibraryError.deductedByFinal(full.number)) { try library.deleteDraft(invoice: deposit.id) }
        try library.markSent(invoice: deposit.id)
        #expect(throws: LibraryError.deductedByFinal(full.number)) { try library.voidInvoice(deposit.id) }
        expectInvoiceRefused(library, deposit.id, final: full.number) { $0.lines[0].rate = Money(dollars: 100) }
    }
}
