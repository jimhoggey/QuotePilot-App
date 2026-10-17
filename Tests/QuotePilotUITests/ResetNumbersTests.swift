import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// File → Reset Quote and Invoice Numbers…: only with no quotes or invoices; otherwise greyed out,
/// with the reason as its tooltip.
@MainActor
@Suite struct ResetNumbersTests {
    @Test func itsGreyedOutWithTheReasonWhileAnyDocumentIsThere() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.resetNumbersBlockedReason?.contains("no quotes or invoices") == true)
        // Choosing it anyway (it can't be, greyed out) changes nothing and asks nothing.
        model.resetNumbers()
        #expect(model.message == nil)
        var library = Library()
        _ = library.newQuote(on: UIFixture.today)
        #expect(throws: LibraryError.documentsStillThere) { try library.resetNumbers() }
    }

    @Test func withNothingLeftItAsksOnceThenNumberingStartsAgain() throws {
        var library = Library()
        let quote = library.newQuote(on: UIFixture.today)
        let invoice = library.newInvoice(on: UIFixture.today)
        try library.deleteDraft(quote: quote.id)
        try library.deleteDraft(invoice: invoice.id)
        #expect(library.nextNumber(.quote) == "Q-0002")
        let model = try UIFixture.model(library)
        #expect(model.resetNumbersBlockedReason == nil)
        model.resetNumbers()
        let box = try #require(model.message)
        #expect(box.title == "Reset Numbers")
        model.respond(try #require(box.choices.first { $0.title == "Reset" }))
        #expect(model.library.nextNumber(.quote) == "Q-0001")
        #expect(model.library.nextNumber(.invoice) == "INV-0001")
        #expect(model.library.activity.first?.message == "Reset numbering: the next quote is Q-0001 and the next invoice INV-0001")
        #expect(model.message == nil)
    }
}
