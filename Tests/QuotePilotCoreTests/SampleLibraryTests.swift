import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct SampleLibraryTests {
    @Test func theSampleBusinessFillsEveryDashboardFigure() throws {
        let library = try SampleLibrary.make(today: Fixture.today)
        let dashboard = Dashboard(library: library, today: Fixture.today)
        #expect(dashboard.waitingTotal == Money(dollars: 285))
        #expect(dashboard.overdueTotal == Money(dollars: 150))
        #expect(dashboard.waiting.first?.daysLate == 5)
        #expect(dashboard.receivedThisMonth == Money(dollars: 1995))
        #expect(dashboard.receivedThisYear == Money(dollars: 1995))
        #expect(dashboard.invoicedThisYear == Money(dollars: 2280))
        #expect(dashboard.openQuotes.count == 2)
        #expect(dashboard.openQuotes.filter(\.expired).count == 1)
        #expect(dashboard.openQuotesTotal == Money(dollars: 620))
        #expect(dashboard.toInvoice.map(\.remaining) == [Money(dollars: 1935)])
        #expect(dashboard.acceptedWorkRemaining == Money(dollars: 1935))
        #expect(dashboard.acceptedJobsOpen == 1)
        #expect(dashboard.acceptedWorkNotInvoiced == Money(dollars: 1935))
        #expect(library.quotes.map { $0.status(on: Fixture.today) } == [.accepted(partly: true), .sent, .expired, .draft])
    }

    @Test func theSampleBusinessIsMadeUp() throws {
        let library = try SampleLibrary.make(today: Fixture.today)
        let text = String(decoding: try Library.makeEncoder().encode(library), as: UTF8.self)
        #expect(text.contains("example.com"))
        #expect(!text.localizedCaseInsensitiveContains("plumb"))
    }
}
