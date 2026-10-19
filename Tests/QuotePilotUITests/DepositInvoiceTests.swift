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
                "Deposit for Q-0001: $900.00 of $1,800.00. The remaining $900.00 will be invoiced when the job is complete.")
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 300)), toInvoice: depositID)
        let partPaid = try UIFixture.model(library)
        #expect(partPaid.depositNote(depositID)?.hasPrefix("Deposit for Q-0001: $900.00 of $1,800.00, $300.00 paid so far.") == true)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 600)), toInvoice: depositID)
        let paid = try UIFixture.model(library)
        #expect(paid.depositNote(depositID) ==
                "Deposit for Q-0001: $900.00 of $1,800.00 paid. The remaining $900.00 will be invoiced when the job is complete.")
    }

    @Test func onceTheFinalIsDraftedTheBannerNamesIt() throws {
        var (library, quoteID, depositID) = try depositLibrary()
        try library.markSent(invoice: depositID)
        let final = try library.draftNextInvoice(forQuote: quoteID, on: today)
        let model = try UIFixture.model(library)
        #expect(model.depositNote(depositID)?.hasSuffix("The remaining $900.00 is on \(final.number).") == true)
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
    /// thirds of the Owing figure's size, so Owing stays the one read first. The two readouts are a
    /// grid: their boxes are one width, with left and right edges lined up.
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
        #expect(model.leftToPayOnJob(deposit.id) != nil, "the sample's paid deposit has the balance left")
        let editor = InvoiceEditorView(model: model, invoiceID: deposit.id)
        let rep = try #require(Snapshot.render(editor.header(deposit).frame(maxHeight: .infinity, alignment: .top),
                                               size: CGSize(width: 778, height: 140), name: "invoice-header-job-readout"))
        #expect(Snapshot.hasContent(rep))
        // The boxes are the only white in the right half: down a column just inside their right
        // edge there are two runs of it, and across the middle of each, the white spans the same columns.
        func isWhite(_ x: Int, _ y: Int) -> Bool {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
            return color.redComponent > 0.95 && color.greenComponent > 0.95 && color.blueComponent > 0.95
        }
        // Only the header's own rows: below it is the window's background.
        let height = Int(NSHostingView(rootView: editor.header(deposit).frame(width: 778)).fittingSize.height)
        let column = rep.pixelsWide - 14
        var runs: [Range<Int>] = []
        var start: Int?
        for y in 0...height {
            let white = y < height && isWhite(column, y)
            if white, start == nil { start = y }
            if !white, let begun = start { runs.append(begun..<y); start = nil }
        }
        // (One-row runs are the bevels' highlight lines and the etched line under the header.)
        runs = runs.filter { $0.count > 4 }
        try #require(runs.count == 2, "expected the two readout boxes, found white runs \(runs)")
        let spans = runs.map { run -> ClosedRange<Int> in
            let y = (run.lowerBound + run.upperBound) / 2
            let xs = (rep.pixelsWide / 2..<rep.pixelsWide).filter { isWhite($0, y) }
            return xs.first!...xs.last!
        }
        #expect(spans[0] == spans[1], "the Owing box spans \(spans[0]), the job's \(spans[1])")
        #expect(runs[0].count > runs[1].count, "the Owing box is the taller one")
    }

    /// A paid deposit's editor at the usual window and at the smallest, for people to look at.
    @Test func aPaidDepositsEditorAtBothSizes() throws {
        let model = try UIFixture.sampleModel()
        model.openInvoice(try #require(model.library.invoices.first { $0.number == "INV-0001" }).id)
        for (width, height, name) in [(1240, 800, "invoice-paid-deposit"), (980, 620, "invoice-paid-deposit-small")] {
            let rep = Snapshot.render(RootView(model: model), size: CGSize(width: width, height: height), name: name)
            #expect(rep.map(Snapshot.hasContent) == true)
        }
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
