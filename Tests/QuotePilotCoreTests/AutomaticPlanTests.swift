import Foundation
import Testing
@testable import QuotePilotCore

/// Brand's 50/50 rule: a draft's plan follows its total until it's chosen by hand, and the quote
/// says what each half comes to.
@Suite struct AutomaticPlanTests {
    let day = Day(year: 2026, month: 10, day: 27)

    func draft(_ library: inout Library, dollars: Int) throws -> Quote {
        var quote = library.newQuote(on: day)
        quote.addLine(LineItem(title: "Work", rate: Money(dollars: dollars)))
        try library.update(quote)
        return try #require(library.quote(quote.id))
    }

    @Test func aboveTheLineIsFiftyFiftyAndTheLineItselfIsNot() {
        let line = Money(dollars: 1000)
        #expect(PaymentPlan.automatic(for: Money(dollars: 1000), splitAbove: line) == .fullAmount)
        #expect(PaymentPlan.automatic(for: Money(dollars: 1000, cents: 1), splitAbove: line) == .fiftyFifty)
        #expect(PaymentPlan.automatic(for: Money(dollars: 5000), splitAbove: .zero) == nil, "$0 turns it off")
    }

    @Test func theSummarySaysWhatEachHalfComesTo() {
        #expect(PaymentPlan.fiftyFifty.summary(for: Money(dollars: 1500), currencyCode: "AUD")
                == "50% ($750.00) when the quote is accepted, 50% ($750.00) on completion")
        #expect(PaymentPlan.fiftyFifty.summary(for: Money(dollars: 1000, cents: 1), currencyCode: "AUD")
                == "50% ($500.01) when the quote is accepted, 50% ($500.00) on completion", "the halves add up")
        #expect(PaymentPlan.fullAmount.summary(for: Money(dollars: 800), currencyCode: "AUD")
                == "Full amount ($800.00) on completion")
    }

    @Test func aDraftsPlanFollowsItsTotal() throws {
        var library = Library()
        let small = try draft(&library, dollars: 800)
        #expect(small.plan == .fullAmount && small.planIsAutomatic)
        let big = try draft(&library, dollars: 1500)
        #expect(big.plan == .fiftyFifty)
        var shrunk = big
        shrunk.lines[0].rate = Money(dollars: 900)
        try library.update(shrunk)
        #expect(library.quote(big.id)?.plan == .fullAmount)
    }

    @Test func aPlanChosenByHandStaysChosen() throws {
        var library = Library()
        var quote = try draft(&library, dollars: 800)
        quote.plan = .fiftyFifty
        try library.update(quote)
        quote = try #require(library.quote(quote.id))
        #expect(quote.plan == .fiftyFifty && !quote.planIsAutomatic)
        quote.lines[0].rate = Money(dollars: 300)
        try library.update(quote)
        #expect(library.quote(quote.id)?.plan == .fiftyFifty)
    }

    @Test func withTheRuleOffNewQuotesStartFiftyFiftyAsBefore() {
        var library = Library()
        library.brand.splitAbove = .zero
        let quote = library.newQuote(on: day)
        #expect(quote.plan == .fiftyFifty && !quote.planIsAutomatic)
    }

    @Test func olderLibrariesKeepTheirQuotesPlansAndGetTheRule() throws {
        var library = Library()
        var quote = try draft(&library, dollars: 300)
        quote.plan = .fiftyFifty
        try library.update(quote)
        var json = try #require(try JSONSerialization.jsonObject(with: Library.makeEncoder().encode(library)) as? [String: Any])
        var quotes = try #require(json["quotes"] as? [[String: Any]])
        quotes[0]["planIsAutomatic"] = nil
        json["quotes"] = quotes
        var brand = try #require(json["brand"] as? [String: Any])
        brand["splitAbove"] = nil
        json["brand"] = brand
        let decoded = try Library.makeDecoder().decode(Library.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.quotes[0].plan == .fiftyFifty && !decoded.quotes[0].planIsAutomatic)
        #expect(decoded.brand.splitAbove == Money(dollars: 1000))
    }
}
