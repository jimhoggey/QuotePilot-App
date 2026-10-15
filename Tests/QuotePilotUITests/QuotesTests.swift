import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct QuotesTests {
    @Test func theEditorRevertsARefusedEdit() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        let quote = model.quoteBinding(quoteID)
        quote.wrappedValue.lines[0].rate = Money(dollars: 999)
        #expect(quote.wrappedValue.lines[0].rate == Money(dollars: 600))
        #expect(model.message?.text == LibraryError.alreadyInvoiced.message)
    }

    @Test func wordingStillChangesOnAnInvoicedQuote() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        model.quoteBinding(quoteID).wrappedValue.title = "Renamed job"
        #expect(model.library.quote(quoteID)?.title == "Renamed job")
        #expect(model.message == nil)
    }

    /// The editor reads `billingLocked(forQuote:)` to grey out the Client, GST and Payment-plan controls
    /// and the lines, and to show the banner. It follows the quote's live invoices, as Core does.
    @Test func aQuoteWithInvoicesLocksItsBillingDetails() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        #expect(model.billingLocked(forQuote: quoteID))
        #expect(AppModel.billingLockedNote
            == "This quote has invoices, so its client, lines and payment plan are locked. Its wording and dates can still change.")

        // What is locked is what Core refuses: the client, the plan, GST and the lines...
        let binding = model.quoteBinding(quoteID)
        for edit: (inout Quote) -> Void in [{ $0.clientID = nil }, { $0.plan = .fullAmount }, { $0.taxed.toggle() },
                                            { $0.addLine(LineItem(title: "Extra", rate: Money(dollars: 10))) },
                                            { $0.lines.removeLast() }] {
            var quote = binding.wrappedValue
            edit(&quote)
            model.message = nil
            binding.wrappedValue = quote
            #expect(model.message?.text == LibraryError.alreadyInvoiced.message)
        }
        // ...and what stays open is what Core allows: wording and dates.
        model.message = nil
        var quote = binding.wrappedValue
        quote.title = "Renamed job"
        quote.summary = "New wording"
        quote.terms = "New terms"
        quote.validUntil = quote.validUntil.adding(days: 7)
        binding.wrappedValue = quote
        #expect(model.message == nil)
        #expect(model.library.quote(quoteID)?.validUntil == quote.validUntil)
    }

    @Test func theLockedQuoteEditorDraws() throws {
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let model = try UIFixture.model(library)
        model.openQuote(quoteID)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 980, height: 620), name: "quote-locked")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func aQuoteWithNoLiveInvoicesIsNotLocked() throws {
        let model = try UIFixture.sampleModel()
        // Sent, accepted without an invoice, and draft quotes have none.
        for quote in model.library.quotes where model.library.invoices(forQuote: quote.id).isEmpty {
            #expect(!model.billingLocked(forQuote: quote.id), "\(quote.number)")
        }
        #expect(!model.billingLocked(forQuote: UUID()))

        // Voiding its only invoice unlocks the quote again: a void invoice doesn't count.
        let (library, quoteID) = try UIFixture.invoicedLibrary()
        let invoiced = try UIFixture.model(library)
        let invoice = try #require(invoiced.library.invoices(forQuote: quoteID).first)
        #expect(invoiced.billingLocked(forQuote: quoteID))
        invoiced.change("test") {
            try $0.markSent(invoice: invoice.id)
            try $0.voidInvoice(invoice.id)
        }
        #expect(!invoiced.billingLocked(forQuote: quoteID))
    }

    @Test func aDraftsLineIDsFollowTheOrderAfterAMove() throws {
        let model = try UIFixture.model()
        model.newQuote()
        let id = try #require(model.openQuoteID)
        let binding = model.quoteBinding(id)
        var quote = binding.wrappedValue
        quote.addLine(LineItem(title: "First", rate: Money(dollars: 100)))
        quote.addLine(LineItem(title: "Second", rate: Money(dollars: 200)))
        binding.wrappedValue = quote
        var moved = binding.wrappedValue
        moved.lines.swapAt(0, 1)
        binding.wrappedValue = moved
        #expect(binding.wrappedValue.lines.map(\.title) == ["Second", "First"])
        #expect(binding.wrappedValue.lines.map(\.code) == ["01", "02"])
    }

    @Test func listRowsShowClientStatusAndTotal() throws {
        let model = try UIFixture.sampleModel()
        let rows = model.library.quotes.map { QuoteRow($0, library: model.library, today: model.today) }
        #expect(rows.map(\.client) == ["Sample Client Pty Ltd", "Example Bakery", "Acme Test Co", "Example Bakery"])
        #expect(rows.map(\.status) == [.accepted(partly: true), .sent, .expired, .draft])
        #expect(rows[1].total == Money(dollars: 620))
    }

    // MARK: Number fields commit as you type

    private let rate: (Money) -> String = { $0.formatted() }

    @Test func aValidChangeCommitsAsYouType() {
        #expect(CommitField<Money>.liveCommit(text: "700", stored: Money(dollars: 600), parse: FieldParser.money)
                == Money(dollars: 700))
        #expect(CommitField<Decimal>.liveCommit(text: "2.5", stored: 2, parse: FieldParser.quantity)
                == Decimal(string: "2.5"))
    }

    @Test func anUnchangedValueDoesNotCommit() {
        #expect(CommitField<Money>.liveCommit(text: "$600.00", stored: Money(dollars: 600), parse: FieldParser.money) == nil)
        #expect(CommitField<Money>.liveCommit(text: "600", stored: Money(dollars: 600), parse: FieldParser.money) == nil)
        #expect(CommitField<Decimal>.liveCommit(text: "2.0", stored: 2, parse: FieldParser.quantity) == nil)
    }

    @Test func halfTypedTextDoesNotCommit() {
        #expect(CommitField<Decimal>.liveCommit(text: "1.", stored: 2, parse: FieldParser.quantity) == nil)
        #expect(CommitField<Decimal>.liveCommit(text: "", stored: 2, parse: FieldParser.quantity) == nil)
        #expect(CommitField<Money>.liveCommit(text: "$", stored: Money(dollars: 600), parse: FieldParser.money) == nil)
        #expect(CommitField<Money>.liveCommit(text: "$-", stored: Money(dollars: 600), parse: FieldParser.money) == nil)
    }

    @Test func leavingWithInvalidTextBeepsAndRestoresTheStoredText() {
        let leaving = CommitField<Money>.onLeave(text: "abc", stored: Money(dollars: 600), format: rate, parse: FieldParser.money)
        #expect(leaving.beep)
        #expect(leaving.text == "$600.00")
    }

    @Test func leavingWithValidTextDoesNotBeep() {
        let same = CommitField<Money>.onLeave(text: "600", stored: Money(dollars: 600), format: rate, parse: FieldParser.money)
        #expect(!same.beep)
        #expect(same.text == "$600.00")
        // Once the typed value has committed, leaving tidies the text to the field's own format.
        let typed = CommitField<Money>.onLeave(text: "1500", stored: Money(dollars: 1500), format: rate, parse: FieldParser.money)
        #expect(!typed.beep)
        #expect(typed.text == "$1,500.00")
    }

    @Test func leavingAnUntouchedFieldWithAnOddStoredValueStaysQuiet() {
        // An imported quantity of 1.234 shows as typed, though the parser wouldn't take it.
        let odd = Decimal(string: "1.234")!
        let leaving = CommitField<Decimal>.onLeave(text: "1.234", stored: odd, format: FieldParser.quantityText,
                                                   parse: FieldParser.quantity)
        #expect(!leaving.beep)
        #expect(leaving.text == "1.234")
    }

    // MARK: Removing a line

    @Test func theRemoveLineQuestionNamesTheLineButNotAnEssay() {
        var line = LineItem(title: "Design", rate: .zero)
        line.code = "02"
        #expect(line.removalName() == "line 02, Design")
        line.title = ""
        #expect(line.removalName() == "line 02")
        line.title = String(repeating: "x", count: 60)
        #expect(line.removalName() == "line 02, " + String(repeating: "x", count: 60))
        line.title = String(repeating: "x", count: 61)
        #expect(line.removalName() == "line 02, " + String(repeating: "x", count: 60) + "…")
    }

    @Test func theQuoteListDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .quotes
        model.selectedQuoteID = model.library.quotes[1].id
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quotes")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theQuoteEditorDraws() throws {
        let model = try UIFixture.sampleModel()
        model.openQuote(model.library.quotes[0].id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quote-editor")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
