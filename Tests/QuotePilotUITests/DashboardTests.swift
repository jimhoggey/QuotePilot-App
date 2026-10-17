import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct DashboardTests {
    /// The four readouts are the money pipeline, left to right, each note saying what its box counts.
    /// The sample: Q-0002 waiting and Q-0003 expired; Q-0001's $1,935 balance not invoiced; INV-0002
    /// and INV-0003 owing; the $1,935 deposit and $60 paid this month.
    @Test func theReadoutNotesSayWhatEachBoxCounts() throws {
        let model = try UIFixture.sampleModel()
        let dashboard = model.dashboard
        #expect(dashboard.openQuotesTotal == Money(dollars: 620))
        #expect(DashboardView.quotesOutNote(dashboard) == "Quoted, waiting on a reply · 1 expired")
        #expect(dashboard.toInvoiceTotal == Money(dollars: 1935))
        #expect(DashboardView.notInvoicedNote(dashboard) == "Accepted, not invoiced yet · 1 job")
        #expect(dashboard.waitingTotal == Money(dollars: 285))
        #expect(DashboardView.waitingNote(dashboard) == "Invoiced, not paid yet · 2 invoices")
        #expect(dashboard.receivedThisYear == Money(dollars: 1995))
        #expect(DashboardView.receivedNote(dashboard, currencyCode: "AUD")
                == "Paid this financial year · This month $1,995.00")

        let empty = Dashboard(library: Library(), today: UIFixture.today)
        #expect(DashboardView.quotesOutNote(empty) == "Quoted, waiting on a reply")
        #expect(DashboardView.notInvoicedNote(empty) == "Accepted, not invoiced yet · 0 jobs")
        #expect(DashboardView.waitingNote(empty) == "Invoiced, not paid yet · 0 invoices")
        #expect(DashboardView.receivedNote(empty, currencyCode: "AUD") == "Paid this financial year · This month $0.00")
    }

    /// In the smallest window (980 wide, 778 beside the section tree) each of the four readouts has
    /// (778 - 2 × 8 padding - 3 × 8 gaps) / 4 - 20 group box padding points inside it. Long notes
    /// shrink to fit there instead of being cut off.
    @Test func theReadoutNotesFitTheSmallestWindow() {
        _ = NSApplication.shared
        let inside = (778 - 2 * DashboardView.gap - 3 * 8) / 4 - 20
        for text in ["Quoted, waiting on a reply · 12 expired", "Accepted, not invoiced yet · 12 jobs",
                     "Invoiced, not paid yet · 12 invoices", "Paid this financial year · This month $12,345.00"] {
            let note = NSHostingView(rootView: Text(text).font(Win95.body).fixedSize())
            #expect(note.fittingSize.width * Readout.noteMinimumScale <= inside, "\(text)")
        }
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
    /// wording when there are none. The total counts only the live ones.
    @Test func theQuotesOutNoteCountsExpiredQuotesToo() throws {
        let model = try UIFixture.sampleModel()
        var dashboard = model.dashboard
        // The sample has Q-0002 waiting and Q-0003 expired.
        let expired = dashboard.openQuotes.filter(\.expired)
        let live = dashboard.openQuotes.filter { !$0.expired }
        #expect(expired.count == 1 && live.count == 1)
        #expect(dashboard.openQuotesTotal == live[0].total)

        dashboard.openQuotes = expired
        #expect(DashboardView.quotesOutNote(dashboard) == "Quoted, waiting on a reply · 1 expired")
        dashboard.openQuotes = live + expired + expired
        #expect(DashboardView.quotesOutNote(dashboard) == "Quoted, waiting on a reply · 2 expired")
        dashboard.openQuotes = live + live
        #expect(DashboardView.quotesOutNote(dashboard) == "Quoted, waiting on a reply")
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
