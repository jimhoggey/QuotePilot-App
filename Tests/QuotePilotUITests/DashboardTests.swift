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

    @Test func theDashboardDraws() throws {
        let model = try UIFixture.sampleModel()
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "dashboard")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func anEmptyDashboardDraws() throws {
        let model = try UIFixture.model()
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "dashboard-empty")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
