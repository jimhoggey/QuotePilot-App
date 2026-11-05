import Foundation
import Testing
@testable import QuotePilotCore

/// Brand → Documents' custom split, such as 30/70: offered on quotes beside 50/50 and the full
/// amount, followed by drafts, kept by quotes once sent, and billed as the deposit and the rest.
@Suite struct CustomSplitTests {
    let day = Day(year: 2026, month: 11, day: 5)

    /// A $1,500 quote on the custom split, with Brand's split at `percent`.
    func library(split percent: Int?) throws -> (Library, UUID) {
        var library = Library()
        library.brand.customSplit = percent
        var quote = library.newQuote(on: day)
        quote.addLine(LineItem(title: "Work", rate: Money(dollars: 1500)))
        quote.plan = .customSplit
        try library.update(quote)
        return (library, quote.id)
    }

    @Test func theSummarySaysWhatEachPartComesTo() throws {
        let (library, id) = try library(split: 30)
        let quote = try #require(library.quote(id))
        #expect(quote.plans == [.fiftyFifty, .fullAmount, .customSplit])
        #expect(quote.depositPercent == 30)
        #expect(quote.summary(of: .customSplit, currencyCode: "AUD")
                == "30% ($450.00) when the quote is accepted, 70% ($1,050.00) on completion")
        #expect(PaymentPlan.splitName(30) == "30/70")
    }

    @Test func withNoCustomSplitQuotesOfferTheTwoPlans() throws {
        let (library, id) = try library(split: nil)
        let quote = try #require(library.quote(id))
        #expect(quote.plans == [.fiftyFifty, .fullAmount])
        #expect(quote.plan == .fiftyFifty, "a custom split with none set falls back to 50/50")
    }

    /// Drafts follow Brand's split; a sent quote keeps the split it was sent with.
    @Test func draftsFollowBrandAndSentQuotesKeepTheirs() throws {
        var (library, sentID) = try library(split: 30)
        try library.markSent(quote: sentID)
        let draftID = library.newQuote(on: day).id
        var draft = try #require(library.quote(draftID))
        draft.plan = .customSplit
        try library.update(draft)

        library.brand.customSplit = 20
        #expect(library.quote(draftID)?.depositPercent == 20)
        #expect(library.quote(sentID)?.depositPercent == 30)

        library.brand.customSplit = nil
        #expect(library.quote(draftID)?.plan == .fiftyFifty)
        #expect(library.quote(sentID)?.depositPercent == 30)
    }

    @Test func theDepositBillsTheSplitAndTheFinalTheRest() throws {
        var (library, id) = try library(split: 30)
        try library.markSent(quote: id)
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01"], declined: []), forQuote: id)
        let deposit = try library.draftNextInvoice(forQuote: id, on: day)
        #expect(deposit.kind == .deposit && deposit.depositPercent == 30)
        #expect(deposit.amount == Money(dollars: 450))
        try library.markSent(invoice: deposit.id)
        let final = try #require(try library.completeJob(quote: id, on: day))
        #expect(final.kind == .final && final.amount == Money(dollars: 1050))
    }

    @Test func aSplitOutsideOneTo99IsAProblem() throws {
        var (library, _) = try library(split: 30)
        #expect(library.problems().isEmpty)
        library.brand.customSplit = 100
        #expect(library.problems().contains { $0.hasPrefix("Brand: the custom split") })
        #expect(library.problems().contains { $0.hasPrefix("Q-0001 has a custom split") })
    }

    /// Libraries from before the custom split have none, and their quotes keep the plan they had.
    @Test func anOlderLibraryHasNoCustomSplit() throws {
        let (library, _) = try library(split: nil)
        let data = try JSONEncoder().encode(library)
        let read = try JSONDecoder().decode(Library.self, from: data)
        #expect(read.brand.customSplit == nil)
        #expect(read.quotes.allSatisfy { $0.customSplit == nil && $0.plans.count == 2 })
    }
}
