import Foundation
import Testing
@testable import QuotePilotCore

/// Deleting any quote or invoice, whatever its stage, for a user who is testing with made-up ones.
@Suite struct DeleteOverrideTests {
    let today = Fixture.today

    /// The library as it would be saved, to prove a refused delete changed nothing at all.
    func saved(_ library: Library) throws -> Data {
        try Library.makeEncoder().encode(library)
    }

    /// Q-0001 accepted 50/50 ($1,080): the deposit INV-0001 ($540) sent and part paid ($200), and the
    /// final INV-0002 ($540 after the deposit) still a draft.
    func invoicedQuote() throws -> (library: Library, quoteID: UUID, deposit: UUID, final: UUID) {
        var (library, id) = Fixture.acceptedLibrary()
        let deposit = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: deposit.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 200)), toInvoice: deposit.id)
        let final = try library.draftNextInvoice(forQuote: id, on: today)
        return (library, id, deposit.id, final.id)
    }

    /// A one-off invoice for $100, sent, with a $10 payment.
    func paidOneOff(in library: inout Library) throws -> Invoice {
        var invoice = library.newInvoice(on: today)
        invoice.lines = [LineItem(title: "Extra work", rate: Money(dollars: 100))]
        try library.update(invoice)
        try library.markSent(invoice: invoice.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 10)), toInvoice: invoice.id)
        return try #require(library.invoice(invoice.id))
    }

    // MARK: Deleting a quote

    @Test func aSentQuoteIsDeletedAndItsNumberIsNeverUsedAgain() throws {
        var (library, id) = Fixture.libraryWithQuote(stage: .sent)
        #expect(library.quote(id)?.stage == .sent)

        try library.deleteQuote(id, includingInvoices: false)

        #expect(library.quotes.isEmpty)
        #expect(library.quote(id) == nil)
        #expect(library.usedNumbers.contains("Q-0001"))
        #expect(library.nextNumber(.quote) == "Q-0002")
        #expect(library.newQuote(on: today).number == "Q-0002")
        #expect(library.activity.first(where: { $0.message.hasPrefix("Deleted") })?.message == "Deleted quote Q-0001 (sent)")
    }

    @Test func aQuoteIsDeletedInEveryStage() throws {
        for stage in [QuoteStage.draft, .sent, .accepted, .declined] {
            var (library, id) = Fixture.libraryWithQuote(stage: stage)
            try library.deleteQuote(id, includingInvoices: false)
            #expect(library.quotes.isEmpty, "\(stage)")
            #expect(library.activity.first?.message == "Deleted quote Q-0001 (\(stage.rawValue))", "\(stage)")
            #expect(library.activity.first?.number == "Q-0001", "\(stage)")
        }
    }

    @Test func aQuoteWithInvoicesAndPaymentsGoesWithAllOfThemAndTheDashboardUpdates() throws {
        var (library, id, deposit, final) = try invoicedQuote()
        let before = Dashboard(library: library, today: today)
        #expect(before.receivedThisYear == Money(dollars: 200))
        #expect(before.invoicedThisYear == Money(dollars: 540), "the sent deposit counts; the draft final doesn't yet")
        #expect(before.waitingTotal == Money(dollars: 340))
        try library.markSent(invoice: final)
        #expect(Dashboard(library: library, today: today).waitingTotal == Money(dollars: 880))

        try library.deleteQuote(id, includingInvoices: true)

        #expect(library.quotes.isEmpty)
        #expect(library.invoices.isEmpty)
        #expect(library.invoice(deposit) == nil)
        #expect(library.invoice(final) == nil)
        #expect(library.paymentsCSV(for: FinancialYear(containing: today)).split(separator: "\n").count == 1,
                "no payment is left to report, only the header row")
        let after = Dashboard(library: library, today: today)
        #expect(after.receivedThisYear == .zero)
        #expect(after.receivedThisMonth == .zero)
        #expect(after.invoicedThisYear == .zero)
        #expect(after.waitingTotal == .zero)
        #expect(after.waiting.isEmpty)
        #expect(after.openQuotes.isEmpty)
        #expect(after.toInvoice.isEmpty)
        // Neither number comes back.
        #expect(library.nextNumber(.quote) == "Q-0002")
        #expect(library.nextNumber(.invoice) == "INV-0003")
        #expect(library.usedNumbers.contains("INV-0001") && library.usedNumbers.contains("INV-0002"))
    }

    @Test func aVoidInvoiceOfTheQuoteGoesToo() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let old = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: old.id)
        try library.voidInvoice(old.id)
        let live = try library.draftNextInvoice(forQuote: id, on: today)
        #expect(library.invoices.count == 2)

        try library.deleteQuote(id, includingInvoices: true)

        #expect(library.invoice(old.id) == nil, "a void invoice still names the quote")
        #expect(library.invoice(live.id) == nil)
        #expect(library.invoices.isEmpty)
        #expect(library.activity.first?.message == "Deleted quote Q-0001 (accepted) and invoices INV-0001, INV-0002")
    }

    @Test func theActivityEntryNamesTheQuoteItsStageAndItsInvoices() throws {
        var (library, id, _, _) = try invoicedQuote()
        let entries = library.activity.count

        try library.deleteQuote(id, includingInvoices: true)

        #expect(library.activity.count == entries + 1, "one entry, however many invoices went")
        #expect(library.activity.first?.message == "Deleted quote Q-0001 (accepted) and invoices INV-0001, INV-0002")
        #expect(library.activity.first?.number == "Q-0001")
    }

    @Test func aSingleInvoiceIsNamedInTheSingular() throws {
        var (library, id) = Fixture.acceptedLibrary()
        try library.draftNextInvoice(forQuote: id, on: today)
        try library.deleteQuote(id, includingInvoices: true)
        #expect(library.activity.first?.message == "Deleted quote Q-0001 (accepted) and invoice INV-0001")
    }

    @Test func invoicesInNumberOrderEvenPastTenThousand() throws {
        var (library, id) = Fixture.acceptedLibrary()
        library.usedNumbers.append("INV-9999")
        let first = try library.draftNextInvoice(forQuote: id, on: today)
        let second = try library.draftNextInvoice(forQuote: id, on: today)
        #expect([first.number, second.number] == ["INV-10000", "INV-10001"])
        // Stored in the other order, as a restored or imported library might have them.
        library.invoices.reverse()
        #expect(library.deletionPreview(quote: id)?.invoiceNumbers == ["INV-10000", "INV-10001"])
        try library.deleteQuote(id, includingInvoices: true)
        #expect(library.activity.first?.message == "Deleted quote Q-0001 (accepted) and invoices INV-10000, INV-10001")
    }

    @Test func otherQuotesAndOneOffInvoicesAreLeftAlone() throws {
        var (library, id, _, _) = try invoicedQuote()
        let other = library.newQuote(on: today)
        let oneOff = try paidOneOff(in: &library)

        try library.deleteQuote(id, includingInvoices: true)

        #expect(library.quotes.map(\.id) == [other.id])
        #expect(library.invoices.map(\.id) == [oneOff.id])
        #expect(library.invoice(oneOff.id)?.payments.count == 1)
        #expect(library.nextNumber(.quote) == "Q-0003")
    }

    @Test func aQuoteWithInvoicesIsRefusedUnlessTheyGoWithIt() throws {
        var (library, id, _, _) = try invoicedQuote()
        let before = try saved(library)

        #expect(throws: LibraryError.quoteHasInvoices(quote: "Q-0001", invoices: ["INV-0001", "INV-0002"])) {
            try library.deleteQuote(id, includingInvoices: false)
        }
        #expect(try saved(library) == before, "a refused delete changes nothing, not even Activity")
        #expect(LibraryError.quoteHasInvoices(quote: "Q-0001", invoices: ["INV-0001", "INV-0002"]).message
            == "Q-0001 has invoices (INV-0001, INV-0002), so they have to be deleted with it.")
    }

    @Test func aQuoteThatIsntThereCantBeDeleted() throws {
        var (library, _) = Fixture.libraryWithQuote()
        let before = try saved(library)
        #expect(throws: LibraryError.notFound) { try library.deleteQuote(UUID(), includingInvoices: true) }
        #expect(try saved(library) == before)
    }

    /// A library saved before the used-numbers list existed knows its numbers only from its documents.
    @Test func aNumberIsKeptEvenWhenTheLibraryNeverListedIt() throws {
        var (library, id, _, _) = try invoicedQuote()
        library.usedNumbers = []
        try library.deleteQuote(id, includingInvoices: true)
        #expect(Set(library.usedNumbers) == ["Q-0001", "INV-0001", "INV-0002"])
        #expect(library.nextNumber(.quote) == "Q-0002")
        #expect(library.nextNumber(.invoice) == "INV-0003")
    }

    @Test func theClientOutlivesTheirDeletedQuote() throws {
        var (library, id) = Fixture.libraryWithQuote()
        let client = try #require(library.clients.first)
        try library.deleteQuote(id, includingInvoices: false)
        #expect(library.clients == [client])
        #expect(library.canDeleteClient(client.id), "with no quote left, the client can be deleted")
    }

    // MARK: Deleting an invoice

    @Test func aSentInvoiceWithPaymentsIsDeletedAndItsNumberIsNeverUsedAgain() throws {
        var library = Library()
        let invoice = try paidOneOff(in: &library)
        let other = library.newInvoice(on: today)
        #expect(Dashboard(library: library, today: today).receivedThisYear == Money(dollars: 10))

        try library.deleteInvoice(invoice.id)

        #expect(library.invoices.map(\.id) == [other.id])
        #expect(library.invoice(invoice.id) == nil)
        #expect(library.usedNumbers.contains("INV-0001"))
        #expect(library.nextNumber(.invoice) == "INV-0003")
        #expect(library.activity.first?.message == "Deleted invoice INV-0001 (sent)")
        #expect(library.activity.first?.number == "INV-0001")
        // Its payment went with it.
        let dashboard = Dashboard(library: library, today: today)
        #expect(dashboard.receivedThisYear == .zero)
    }

    @Test func anInvoiceIsDeletedInEveryStage() throws {
        var library = Library()
        let draft = library.newInvoice(on: today)
        let sent = library.newInvoice(on: today)
        let void = library.newInvoice(on: today)
        try library.markSent(invoice: sent.id)
        try library.markSent(invoice: void.id)
        try library.voidInvoice(void.id)

        for (invoice, word) in [(draft, "draft"), (sent, "sent"), (void, "void")] {
            try library.deleteInvoice(invoice.id)
            #expect(library.invoice(invoice.id) == nil, "\(word)")
            #expect(library.activity.first?.message == "Deleted invoice \(invoice.number) (\(word))", "\(word)")
        }
        #expect(library.invoices.isEmpty)
    }

    @Test func deletingOneInvoiceLeavesItsQuoteAndTheOtherInvoice() throws {
        var (library, id, deposit, final) = try invoicedQuote()
        try library.deleteInvoice(final)
        #expect(library.quote(id) != nil)
        #expect(library.invoices.map(\.id) == [deposit])
        // The quote can draft its closing invoice again, under a new number.
        #expect(library.nextInvoiceKind(forQuote: id) == .final)
        #expect(try library.draftNextInvoice(forQuote: id, on: today).number == "INV-0003")
    }

    @Test func aDepositTheFinalStillDeductsIsRefusedAndNothingChanges() throws {
        var (library, _, deposit, _) = try invoicedQuote()
        let before = try saved(library)

        #expect(throws: LibraryError.depositStillDeducted("INV-0002")) { try library.deleteInvoice(deposit) }
        #expect(try saved(library) == before, "a refused delete changes nothing, not even Activity")
        #expect(library.invoice(deposit)?.payments.count == 1)
        #expect(LibraryError.depositStillDeducted("INV-0005").message
            == "INV-0005 deducts this deposit. Delete INV-0005 first.")
        #expect(LibraryError.depositStillDeducted("INV-0005").localizedDescription
            == LibraryError.depositStillDeducted("INV-0005").message)
    }

    @Test func theDepositCanGoOnceItsFinalIsDeleted() throws {
        var (library, id, deposit, final) = try invoicedQuote()
        try library.deleteInvoice(final)
        try library.deleteInvoice(deposit)
        #expect(library.invoices.isEmpty)
        #expect(library.quote(id) != nil)
        #expect(library.nextNumber(.invoice) == "INV-0003")
    }

    @Test func aVoidFinalNoLongerHoldsTheDepositBack() throws {
        var (library, _, deposit, final) = try invoicedQuote()
        try library.markSent(invoice: final)
        try library.voidInvoice(final)
        try library.deleteInvoice(deposit)
        #expect(library.invoice(deposit) == nil)
        #expect(library.invoice(final)?.stage == .void)
    }

    @Test func aFinalWithPaymentsCanBeDeletedAndThenItsDeposit() throws {
        var (library, _, deposit, final) = try invoicedQuote()
        try library.markSent(invoice: final)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 100)), toInvoice: final)
        try library.deleteInvoice(final)
        #expect(library.invoice(final) == nil)
        try library.deleteInvoice(deposit)
        #expect(library.invoices.isEmpty)
    }

    @Test func anInvoiceThatIsntThereCantBeDeleted() throws {
        var (library, _, _, _) = try invoicedQuote()
        let before = try saved(library)
        #expect(throws: LibraryError.notFound) { try library.deleteInvoice(UUID()) }
        #expect(try saved(library) == before)
    }

    @Test func anInvoiceNumberIsKeptEvenWhenTheLibraryNeverListedIt() throws {
        var library = Library()
        let invoice = library.newInvoice(on: today)
        library.usedNumbers = []
        try library.deleteInvoice(invoice.id)
        #expect(library.usedNumbers == ["INV-0001"])
        #expect(library.nextNumber(.invoice) == "INV-0002")
    }

    // MARK: What a delete would remove

    @Test func aQuotePreviewListsItsInvoicesAndWhetherAnyHavePayments() throws {
        var (library, id, _, final) = try invoicedQuote()
        let preview = try #require(library.deletionPreview(quote: id))
        #expect(preview == DeletionPreview(number: "Q-0001", invoiceNumbers: ["INV-0001", "INV-0002"], hasPayments: true))

        // Payments on the deposit are what count; none on the final changes nothing.
        try library.deleteInvoice(final)
        #expect(library.deletionPreview(quote: id)?.invoiceNumbers == ["INV-0001"])
        #expect(library.deletionPreview(quote: id)?.hasPayments == true)
    }

    @Test func aQuotePreviewWithNoInvoicesOrNoPaymentsSaysSo() throws {
        let (library, id) = Fixture.libraryWithQuote()
        #expect(library.deletionPreview(quote: id) == DeletionPreview(number: "Q-0001", invoiceNumbers: [], hasPayments: false))

        var (accepted, quoteID) = Fixture.acceptedLibrary()
        try accepted.draftNextInvoice(forQuote: quoteID, on: today)
        #expect(accepted.deletionPreview(quote: quoteID)
            == DeletionPreview(number: "Q-0001", invoiceNumbers: ["INV-0001"], hasPayments: false))
    }

    @Test func aVoidInvoiceIsListedInTheQuotePreview() throws {
        var (library, id) = Fixture.acceptedLibrary()
        let old = try library.draftNextInvoice(forQuote: id, on: today)
        try library.markSent(invoice: old.id)
        try library.voidInvoice(old.id)
        #expect(library.deletionPreview(quote: id)?.invoiceNumbers == ["INV-0001"])
    }

    @Test func anInvoicePreviewSaysWhetherItHasPayments() throws {
        let (library, _, deposit, final) = try invoicedQuote()
        #expect(library.deletionPreview(invoice: deposit)
            == DeletionPreview(number: "INV-0001", invoiceNumbers: [], hasPayments: true))
        #expect(library.deletionPreview(invoice: final)
            == DeletionPreview(number: "INV-0002", invoiceNumbers: [], hasPayments: false))
    }

    @Test func thereIsNoPreviewForSomethingThatIsntThere() throws {
        let (library, _, _, _) = try invoicedQuote()
        #expect(library.deletionPreview(quote: UUID()) == nil)
        #expect(library.deletionPreview(invoice: UUID()) == nil)
    }

    // MARK: Draft deletes are unchanged

    @Test func deleteDraftStillRefusesAnythingButADraft() throws {
        var (library, id) = Fixture.libraryWithQuote(stage: .sent)
        #expect(throws: LibraryError.notDraft) { try library.deleteDraft(quote: id) }
        #expect(library.quote(id) != nil)
    }
}
