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
