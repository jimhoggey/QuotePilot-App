import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct DashboardTests {
    /// The Left on accepted jobs note counts the jobs not fully paid and says how much of them isn't
    /// invoiced yet, which is the Still to invoice list's sum.
    @Test func theAcceptedWorkNoteCountsJobsAndWhatsNotInvoiced() throws {
        let model = try UIFixture.sampleModel()
        var dashboard = model.dashboard
        // The sample's Q-0001: $3,870 accepted, the $1,935 deposit paid, the balance not invoiced.
        #expect(dashboard.acceptedWorkRemaining == Money(dollars: 1935))
        #expect(DashboardView.acceptedWorkNote(dashboard, currencyCode: "AUD") == "1 job · $1,935.00 not invoiced yet")
        dashboard.acceptedJobsOpen = 3
        dashboard.acceptedWorkNotInvoiced = Money(dollars: 4500)
        #expect(DashboardView.acceptedWorkNote(dashboard, currencyCode: "AUD") == "3 jobs · $4,500.00 not invoiced yet")
        let empty = Dashboard(library: Library(), today: UIFixture.today)
        #expect(DashboardView.acceptedWorkNote(empty, currencyCode: "AUD") == "No accepted jobs open")
    }

    /// In the smallest window (980 wide, 778 beside the section tree) each of the four readouts has
    /// (778 - 2 × 8 padding - 3 × 8 gaps) / 4 - 20 group box padding points inside it. A long note
    /// shrinks to fit there instead of being cut off.
    @Test func theAcceptedWorkNoteFitsTheSmallestWindow() {
        _ = NSApplication.shared
        let inside = (778 - 2 * DashboardView.gap - 3 * 8) / 4 - 20
        let note = NSHostingView(rootView: Text("3 jobs · $4,500.00 not invoiced yet").font(Win95.body).fixedSize())
        #expect(note.fittingSize.width * Readout.noteMinimumScale <= inside)
    }

    /// With the Overdue readout gone, an overdue invoice still shows in red in Waiting to be paid
    /// ("Overdue 5 d"), and the status bar counts it.
    @Test func overdueInvoicesStillShowInTheListAndStatusBar() throws {
        let model = try UIFixture.sampleModel()
        let late = try #require(model.dashboard.waiting.first)
        let status = try #require(model.library.invoice(late.invoiceID)?.status(on: model.today))
        #expect(status.listLabel == "Overdue 5 d")
        #expect(status.isAlert)
        #expect(StatusBarText.items(model.dashboard, lastSaved: nil, currencyCode: "AUD")[1] == "1 invoice overdue")
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
