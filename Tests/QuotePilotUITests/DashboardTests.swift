import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct DashboardTests {
    @Test func theOverdueNoteNamesTheOldest() throws {
        let model = try UIFixture.sampleModel()
        #expect(DashboardView.overdueNote(model.dashboard) == "1 invoice, 5 days late")
        let empty = Dashboard(library: Library(), today: UIFixture.today)
        #expect(DashboardView.overdueNote(empty) == "Nothing overdue")
    }

    /// The Quotes out note counts the expired quotes the list under it shows, and keeps the plain
    /// wording when there are none.
    @Test func theQuotesOutNoteCountsExpiredQuotesToo() throws {
        let model = try UIFixture.sampleModel()
        var dashboard = model.dashboard
        // The sample has Q-0002 waiting and Q-0003 expired.
        #expect(DashboardView.quotesOutNote(dashboard) == "1 waiting on a reply · 1 expired")
        let expired = dashboard.openQuotes.filter(\.expired)
        let live = dashboard.openQuotes.filter { !$0.expired }
        #expect(expired.count == 1 && live.count == 1)

        dashboard.openQuotes = expired
        #expect(DashboardView.quotesOutNote(dashboard) == "0 waiting on a reply · 1 expired")
        dashboard.openQuotes = live + expired + expired
        #expect(DashboardView.quotesOutNote(dashboard) == "1 waiting on a reply · 2 expired")
        dashboard.openQuotes = live
        #expect(DashboardView.quotesOutNote(dashboard) == "1 quote waiting on a reply")
        dashboard.openQuotes = live + live
        #expect(DashboardView.quotesOutNote(dashboard) == "2 quotes waiting on a reply")
        let empty = Dashboard(library: Library(), today: UIFixture.today)
        #expect(DashboardView.quotesOutNote(empty) == "0 quotes waiting on a reply")
    }

    /// The smallest window (980 wide) leaves 778 beside the section tree. The two lists that share a row (quotes, jobs) must fit
    /// there side by side with a classic scroller in each, or the row pushes the tree off the window.
    @Test func theBottomListsFitTheSmallestWindow() {
        #expect(DetailsLayout.classicScrollerWidth == 17)
        #expect(DashboardView.bottomRowMinimum(scroller: DetailsLayout.classicScrollerWidth) <= 778)
        #expect(DashboardView.bottomRowMinimum(scroller: 0) <= 778)
    }

    @Test func theDashboardDraws() throws {
        let model = try UIFixture.sampleModel()
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "dashboard")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// A new library shows the Getting started box above the readouts (snapshot: dashboard-empty).
    @Test func anEmptyDashboardDraws() throws {
        let model = try UIFixture.model()
        #expect(GettingStarted(library: model.library).isShowing)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "dashboard-empty")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
