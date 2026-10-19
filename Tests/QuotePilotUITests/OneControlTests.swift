import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// One control per action: on any one screen an action has exactly one button. The step bar's Open
/// button is that control while it shows; with View → Show Steps off, or when the bar has no button
/// for it, the screen's own button shows instead. The same action has the same label everywhere.
@MainActor
@Suite struct OneControlTests {
    let today = UIFixture.today

    /// The fixture's quote Q-0001 for $1,800, with its 50% deposit INV-0001 for $900 drafted.
    func depositLibrary() throws -> (library: Library, quoteID: UUID, depositID: UUID) {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let deposit = try #require(library.invoices.first { $0.kind == .deposit })
        return (library, quoteID, deposit.id)
    }

    func banner(_ invoiceID: UUID, in library: Library, stepsShown: Bool) throws -> Bool {
        let invoice = try #require(library.invoice(invoiceID))
        let quote = try #require(invoice.quoteID.flatMap { library.quote($0) })
        return QuoteSourceBanner.showsOpenButton(invoice, quote: quote, in: library, today: today,
                                                 stepsShown: stepsShown)
    }

    func barOffers(_ invoiceID: UUID, in library: Library, stepsShown: Bool) throws -> Bool {
        let invoice = try #require(library.invoice(invoiceID))
        let quoteID = try #require(invoice.quoteID)
        let next = NextStep.forInvoice(invoice, in: library, today: today)
        return StepBar.offersOpen(quoteID, next: next, stepsShown: stepsShown)
    }

    // MARK: The invoice's quote banner

    /// A paid deposit's next step is Job Complete on the quote, so the step bar has Open Q-0001. With
    /// steps on, that is the one button: the banner has none. With steps off, the banner has it.
    @Test func aPaidDepositOpensItsQuoteFromTheStepBarOnly() throws {
        var (library, _, depositID) = try depositLibrary()
        try library.markSent(invoice: depositID)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 900)), toInvoice: depositID)

        #expect(try barOffers(depositID, in: library, stepsShown: true))
        #expect(try banner(depositID, in: library, stepsShown: true) == false)

        #expect(try barOffers(depositID, in: library, stepsShown: false) == false)
        #expect(try banner(depositID, in: library, stepsShown: false))
    }

    /// Any other invoice from a quote: the bar has no button for the quote, so the banner keeps its own,
    /// steps on or off.
    @Test func otherwiseTheBannerHasTheButton() throws {
        var (library, quoteID, depositID) = try depositLibrary()
        for shown in [true, false] {
            #expect(try banner(depositID, in: library, stepsShown: shown), "a draft deposit, steps \(shown)")
        }
        try library.markSent(invoice: depositID)
        for shown in [true, false] {
            #expect(try banner(depositID, in: library, stepsShown: shown), "an unpaid deposit, steps \(shown)")
        }
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 900)), toInvoice: depositID)
        let final = try #require(try library.completeJob(quote: quoteID, on: today))
        for shown in [true, false] {
            #expect(try banner(final.id, in: library, stepsShown: shown), "the final, steps \(shown)")
            // Once the job is complete the deposit's next step no longer opens the quote either.
            #expect(try banner(depositID, in: library, stepsShown: shown), "the paid deposit after Job Complete, steps \(shown)")
        }
    }

    /// The banner's button says what the bar's says: "Open Q-0001", naming the quote.
    @Test func theBannerAndTheBarNameTheQuoteTheSameWay() throws {
        var (library, quoteID, depositID) = try depositLibrary()
        try library.markSent(invoice: depositID)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 900)), toInvoice: depositID)
        let quote = try #require(library.quote(quoteID))
        let next = NextStep.forInvoice(try #require(library.invoice(depositID)), in: library, today: today)
        let target = try #require(next.openTarget)
        #expect(QuoteSourceBanner.openTitle(quote) == "Open Q-0001")
        #expect(QuoteSourceBanner.openTitle(quote) == "Open \(target.number)")
    }

    // MARK: Save PDF

    /// The editors have no Save PDF… of their own: the toolbar's Save PDF is on with any quote or
    /// invoice open, so it is the one control.
    @Test func theToolbarsSavePDFServesEveryOpenEditor() throws {
        let model = try UIFixture.sampleModel()
        for quote in model.library.quotes {
            model.openQuote(quote.id)
            #expect(model.canExportPDF, "\(quote.number) open")
        }
        for invoice in model.library.invoices {
            model.openInvoice(invoice.id)
            #expect(model.canExportPDF, "\(invoice.number) open")
        }
    }

    // MARK: One outlined button

    /// Send by Mail… has the heavy outline only on a draft. On a sent invoice with money owing the
    /// outlined button is Record Payment (the New payment area shows), so there is never a second.
    @Test func anInvoiceOutlinesSendOnlyWhileItIsADraft() throws {
        var (library, _, depositID) = try depositLibrary()
        let draft = try #require(library.invoice(depositID))
        #expect(InvoiceEditorView.sendIsDefault(draft))
        try library.markSent(invoice: depositID)
        let sent = try #require(library.invoice(depositID))
        #expect(InvoiceEditorView.sendIsDefault(sent) == false)
        #expect(try UIFixture.model(library).newPaymentEntry(for: depositID) != nil, "Record Payment shows")
    }

    /// A quote: Send by Mail… is outlined while it is a draft and not once it is sent or accepted, when
    /// the next step is the reply or invoicing.
    @Test func aQuoteOutlinesSendOnlyWhileItIsADraft() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let accepted = try #require(library.quote(quoteID))
        #expect(accepted.stage == .accepted)
        #expect(QuoteEditorView.sendIsDefault(accepted) == false)
        var sent = accepted
        sent.stage = .sent
        #expect(QuoteEditorView.sendIsDefault(sent) == false)
        var draft = accepted
        draft.stage = .draft
        #expect(QuoteEditorView.sendIsDefault(draft))
    }

    /// The bar's Open button has to be on screen for the banner to leave its own out: at the smallest
    /// window, the paid deposit's first row still leaves the bar room for at least its short form.
    @Test func theBarsOpenButtonFitsTheSmallestWindow() throws {
        let model = try UIFixture.sampleModel()
        let deposit = try #require(model.library.invoices.first { $0.number == "INV-0001" })
        let next = NextStep.forInvoice(deposit, in: model.library, today: model.today)
        #expect(next.openTarget?.kind == "quote", "the sample's INV-0001 is a paid deposit")
        let suite = "QuotePilotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        _ = NSApplication.shared
        let row = InvoiceEditorView(model: model, invoiceID: deposit.id, stepDefaults: defaults).titleRow(deposit)
        let width = NSHostingView(rootView: row).fittingSize.width
        let room = StepBarTests.smallSection - width - StepBarRegion.leadingGap
        #expect(room >= StepBarRegion.minimumWidth, "the bar has \(room) at the smallest window")
    }
}
