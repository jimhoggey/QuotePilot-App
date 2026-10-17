import Foundation
import Testing
@testable import QuotePilotCore

/// A draft's number typed in by hand.
@Suite struct RenumberingTests {
    let today = Fixture.today

    @Test func numbersAreReadAsTyped() {
        #expect(Library.parseNumber("Q-0012", .quote) == "Q-0012")
        #expect(Library.parseNumber(" q-12 ", .quote) == "Q-0012")
        #expect(Library.parseNumber("12", .quote) == "Q-0012")
        #expect(Library.parseNumber("inv-7", .invoice) == "INV-0007")
        #expect(Library.parseNumber("Q-12345", .quote) == "Q-12345")
        for bad in ["", "Q-", "Q-0", "INV-0012", "12a", "Q-1.5", "-3"] {
            #expect(Library.parseNumber(bad, .quote) == nil, "\(bad)")
        }
    }

    @Test func aDraftQuoteTakesANewNumberAndNumberingCarriesOnFromIt() throws {
        var library = Library()
        let quote = library.newQuote(on: today)
        try library.renumber(quote: quote.id, to: "40")
        #expect(library.quote(quote.id)?.number == "Q-0040")
        #expect(library.activity.first?.message == "Changed quote Q-0001's number to Q-0040")
        #expect(library.activity.first?.number == "Q-0040")
        #expect(!library.numberUsedBefore("Q-0040"))
        // Automatic numbering goes on from the highest used, and Q-0001 is never handed out again.
        #expect(library.newQuote(on: today).number == "Q-0041")
        // A lower number is fine too; numbering still carries on from the highest.
        let third = library.newQuote(on: today)
        try library.renumber(quote: third.id, to: "Q-0005")
        #expect(library.nextNumber(.quote) == "Q-0043")
    }

    @Test func aNumberAnotherDocumentHasIsRefused() throws {
        var library = Library()
        let first = library.newQuote(on: today)
        let second = library.newQuote(on: today)
        #expect(throws: LibraryError.numberInUse("Q-0001")) { try library.renumber(quote: second.id, to: "q-1") }
        #expect(library.quote(second.id)?.number == "Q-0002")
        // Its own number is no change, and logs nothing.
        let logged = library.activity.count
        try library.renumber(quote: first.id, to: "Q-0001")
        #expect(library.activity.count == logged)
        #expect(throws: LibraryError.notANumber("abc", "Q-")) { try library.renumber(quote: first.id, to: "abc") }
    }

    @Test func aDeletedDocumentsNumberCanBeUsedAgainAndIsNoted() throws {
        var library = Library()
        let deleted = library.newInvoice(on: today)
        let kept = library.newInvoice(on: today)
        try library.deleteDraft(invoice: deleted.id)
        try library.renumber(invoice: kept.id, to: "INV-0001")
        #expect(library.invoice(kept.id)?.number == "INV-0001")
        #expect(library.numberUsedBefore("INV-0001"))
        #expect(library.activity.first?.message == "Changed invoice INV-0002's number to INV-0001 (used before)")
        #expect(library.nextNumber(.invoice) == "INV-0003")
    }

    @Test func onlyDraftsTakeANewNumber() throws {
        var (library, id) = Fixture.libraryWithQuote(stage: .sent)
        #expect(throws: LibraryError.numberOnlyOnDrafts) { try library.renumber(quote: id, to: "9") }
        let invoice = library.newInvoice(on: today)
        try library.markSent(invoice: invoice.id)
        #expect(throws: LibraryError.numberOnlyOnDrafts) { try library.renumber(invoice: invoice.id, to: "9") }
    }
}
