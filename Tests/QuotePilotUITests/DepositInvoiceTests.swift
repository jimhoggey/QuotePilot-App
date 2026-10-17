import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// A deposit invoice says it is only part of the job: the banner, the line under the readout, and
/// the next step once it's paid.
@MainActor
@Suite struct DepositInvoiceTests {
    let today = UIFixture.today

    /// The fixture's quote Q-0001 for $1,800, with its 50% deposit INV-0001 for $900 drafted.
    func depositLibrary() throws -> (library: Library, quoteID: UUID, depositID: UUID) {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let deposit = try #require(library.invoices.first { $0.kind == .deposit })
        return (library, quoteID, deposit.id)
    }

    @Test func theBannerSaysWhatTheDepositIsOutOfTheJob() throws {
        var (library, _, depositID) = try depositLibrary()
        try library.markSent(invoice: depositID)
        let model = try UIFixture.model(library)
        #expect(model.depositNote(depositID) ==
                "Deposit for Q-0001: $900.00 of $1,800.00. The $900.00 balance is invoiced when the job is complete.")
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 300)), toInvoice: depositID)
        let partPaid = try UIFixture.model(library)
        #expect(partPaid.depositNote(depositID)?.hasPrefix("Deposit for Q-0001: $900.00 of $1,800.00, $300.00 paid so far.") == true)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 600)), toInvoice: depositID)
        let paid = try UIFixture.model(library)
        #expect(paid.depositNote(depositID) ==
                "Deposit for Q-0001: $900.00 of $1,800.00 paid. The $900.00 balance is invoiced when the job is complete.")
    }

    @Test func onceTheFinalIsDraftedTheBannerNamesIt() throws {
        var (library, quoteID, depositID) = try depositLibrary()
        try library.markSent(invoice: depositID)
        let final = try library.draftNextInvoice(forQuote: quoteID, on: today)
        let model = try UIFixture.model(library)
        #expect(model.depositNote(depositID)?.hasSuffix("The $900.00 balance is on \(final.number).") == true)
        // Not for the final itself.
        #expect(model.depositNote(final.id) == nil)
    }

    @Test func leftToPayOnTheJobCountsEveryPayment() throws {
        var (library, quoteID, depositID) = try depositLibrary()
        try library.markSent(invoice: depositID)
        #expect(library.leftToPay(onQuote: quoteID) == Money(dollars: 1800))
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 900)), toInvoice: depositID)
        #expect(library.leftToPay(onQuote: quoteID) == Money(dollars: 900))
        let final = try library.draftNextInvoice(forQuote: quoteID, on: today)
        #expect(library.leftToPay(onQuote: quoteID) == Money(dollars: 900))
        #expect(try UIFixture.model(library).leftToPayOnJob(depositID) == Money(dollars: 900))
        try library.markSent(invoice: final.id)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 900)), toInvoice: final.id)
        #expect(library.leftToPay(onQuote: quoteID) == .zero)
        let model = try UIFixture.model(library)
        // Nothing left, so the deposit's header has no job readout.
        #expect(model.leftToPayOnJob(depositID) == nil)
        #expect(model.leftToPayOnJob(final.id) == nil)
    }

    /// "Left to pay on this job" is a readout of its own: the amount in a sunken box at about two
    /// thirds of the Owing figure's size, so Owing stays the one read first, and its row is no wider
    /// than the Owing row above it, so the header doesn't grow.
    @Test func theJobReadoutIsASmallerReadoutUnderOwing() throws {
        #expect((0.6...0.7).contains(Win95.smallReadoutSize / Win95.readoutSize))
        // Monospaced type is as wide as it is big, so the drawn widths say the same.
        func width<V: View>(_ view: V) -> CGFloat {
            _ = NSApplication.shared
            return NSHostingView(rootView: view).fittingSize.width
        }
        let big = width(Text("$1,935.00").font(Win95.readout).fixedSize())
        let small = width(Text("$1,935.00").font(Win95.smallReadout).fixedSize())
        #expect((0.6...0.7).contains(small / big), "the job amount is \(small / big) of Owing's width")

        let model = try UIFixture.sampleModel()
        let deposit = try #require(model.library.invoices.first { $0.number == "INV-0001" })
        let left = try #require(model.leftToPayOnJob(deposit.id), "the sample's paid deposit has the balance left")
        let editor = InvoiceEditorView(model: model, invoiceID: deposit.id)
        let job = width(editor.jobReadout(model.money(left)))
        let owing = width(HStack(spacing: 10) {
            Text("Owing on this invoice").font(Win95.label).fixedSize()
            Text(model.money(deposit.owing)).font(Win95.readout).padding(.horizontal, 8)
                .frame(minWidth: 190).win95Sunken()
        })
        #expect(job <= owing, "the job readout is \(job) wide, the Owing row \(owing)")
        let rep = Snapshot.render(editor.header(deposit), size: CGSize(width: 778, height: 140), name: "invoice-header-job-readout")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func aPaidDepositsNextStepIsJobCompleteOnTheQuote() throws {
        var (library, quoteID, depositID) = try depositLibrary()
        try library.markSent(invoice: depositID)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 900)), toInvoice: depositID)
        let deposit = try #require(library.invoice(depositID))
        let next = NextStep.forInvoice(deposit, in: library, today: today)
        #expect(next.sentence == "Deposit paid. When the job is done, open Q-0001 and press Job Complete.")
        #expect(next.action == .openQuote(quoteID, number: "Q-0001"))
        #expect(next.openTarget?.kind == "quote")
        // Once the job is complete the ordinary paid sentence is back.
        _ = try library.completeJob(quote: quoteID, on: today)
        let after = NextStep.forInvoice(try #require(library.invoice(depositID)), in: library, today: today)
        #expect(after.sentence == "Paid in full. Send Receipt… if the client wants one.")
    }
}
