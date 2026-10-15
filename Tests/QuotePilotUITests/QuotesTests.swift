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
