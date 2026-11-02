import Foundation
import Testing
@testable import QuotePilotCore

/// The Done ticks: the user's own tracker, kept at any stage and tidied when lines go.
@Suite struct DoneLinesTests {
    @Test func ticksStayOnAnInvoicedQuote() throws {
        var (library, id) = Fixture.libraryWithQuote()
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01", "02"], declined: ["03"]), forQuote: id)
        _ = try library.draftNextInvoice(forQuote: id, on: Fixture.today)
        var quote = try #require(library.quote(id))
        quote.doneLines = [quote.lines[0].id]
        try library.update(quote)
        #expect(library.quote(id)?.doneLines == [quote.lines[0].id])
    }

    @Test func aRemovedLinesTickGoesWithIt() throws {
        var (library, id) = Fixture.libraryWithQuote(stage: .draft)
        var quote = try #require(library.quote(id))
        quote.doneLines = Set(quote.lines.map(\.id))
        let removed = quote.lines.removeLast()
        try library.update(quote)
        #expect(library.quote(id)?.doneLines.contains(removed.id) == false)
        #expect(library.quote(id)?.doneLines.count == 2)
    }

    @Test func olderLibrariesHaveNoTicksAndNoColumn() throws {
        let (library, _) = Fixture.libraryWithQuote()
        var json = try #require(try JSONSerialization.jsonObject(with: Library.makeEncoder().encode(library)) as? [String: Any])
        var quotes = try #require(json["quotes"] as? [[String: Any]])
        quotes[0]["doneLines"] = nil
        json["quotes"] = quotes
        var brand = try #require(json["brand"] as? [String: Any])
        brand["showsDoneColumn"] = nil
        json["brand"] = brand
        let decoded = try Library.makeDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.quotes[0].doneLines.isEmpty)
        #expect(!decoded.brand.showsDoneColumn)
    }
}
