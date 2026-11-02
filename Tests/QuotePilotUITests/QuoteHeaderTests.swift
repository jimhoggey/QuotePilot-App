import Foundation
import QuotePilotCore
import SwiftUI
import Testing
@testable import QuotePilotUI

/// The quote header offers one button per action, and only the ones that still apply.
@MainActor
@Suite struct QuoteHeaderTests {
    func quote(_ stage: QuoteStage) -> Quote {
        Quote(number: "Q-0001", issued: UIFixture.today, validUntil: UIFixture.today, stage: stage)
    }

    @Test func sendingIsForDraftsAndQuotesStillOut() {
        #expect(QuoteEditorView.showsSend(quote(.draft)))
        #expect(QuoteEditorView.showsSend(quote(.sent)))
        #expect(!QuoteEditorView.showsSend(quote(.accepted)))
        #expect(!QuoteEditorView.showsSend(quote(.declined)))
    }

    @Test func anAnsweredQuoteOffersToChangeTheAcceptance() {
        #expect(QuoteEditorView.acceptanceButton(quote(.draft), invoiced: false) == nil)
        #expect(QuoteEditorView.acceptanceButton(quote(.sent), invoiced: false) == "Record Acceptance…")
        #expect(QuoteEditorView.acceptanceButton(quote(.accepted), invoiced: false) == "Change Acceptance…")
        #expect(QuoteEditorView.acceptanceButton(quote(.declined), invoiced: false) == "Change Acceptance…")
        #expect(QuoteEditorView.acceptanceButton(quote(.accepted), invoiced: true) == nil)
    }

    /// Job Complete drafts the closing invoice, so Draft Invoice Now never sits beside it doing the same.
    @Test func draftInvoiceNowNeverDuplicatesJobComplete() {
        #expect(!QuoteEditorView.showsDraftInvoiceNow(next: .full, canCompleteJob: true))
        #expect(!QuoteEditorView.showsDraftInvoiceNow(next: .final, canCompleteJob: true))
        #expect(QuoteEditorView.showsDraftInvoiceNow(next: .deposit, canCompleteJob: true))
        #expect(QuoteEditorView.showsDraftInvoiceNow(next: .full, canCompleteJob: false), "job done, invoice voided")
        #expect(!QuoteEditorView.showsDraftInvoiceNow(next: nil, canCompleteJob: false))
    }

    @Test func theDoneColumnDraws() throws {
        let model = try UIFixture.sampleModel()
        var brand = model.library.brand
        brand.showsDoneColumn = true
        model.updateBrand(brand)
        let quote = try #require(model.library.quotes.first)
        var ticked = quote
        ticked.doneLines = [quote.lines[0].id]
        model.updateQuote(ticked)
        model.openQuote(quote.id)
        #expect(model.library.quote(quote.id)?.doneLines == [quote.lines[0].id])
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quote-done-column")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
