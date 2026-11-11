import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct ShellTests {
    @Test func theStatusBarRepeatsTheKeyTotals() throws {
        var library = Library()
        var invoice = library.newInvoice(on: UIFixture.today.adding(days: -20))
        invoice.lines = [LineItem(title: "Monthly care", rate: Money(dollars: 150))]
        try library.update(invoice)
        try library.markSent(invoice: invoice.id)
        let dashboard = Dashboard(library: library, today: UIFixture.today)

        let items = StatusBarText.items(dashboard, lastSaved: nil, currencyCode: "AUD")
        #expect(items == ["Waiting: $150.00", "1 invoice overdue", "Received FY 2026–27: $0.00", "No changes yet"])

        let saved = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14, minute: 41))!
        #expect(StatusBarText.items(dashboard, lastSaved: saved, currencyCode: "AUD")[3].hasPrefix("Saved 2:41"))

        // A coin, a warning while one is overdue, a tick, and a floppy disk by the time of the last save.
        #expect(StatusBarText.icons(dashboard, lastSaved: nil) == [.payment, .warning, .tick, nil])
        #expect(StatusBarText.icons(dashboard, lastSaved: saved) == [.payment, .warning, .tick, .floppy])
        let note = StatusNote(text: "INV-0001 marked as sent", at: saved)
        #expect(StatusBarText.icons(dashboard, lastSaved: saved, note: note)[3] == nil, "a note has no disk")
        let calm = Dashboard(library: Library(), today: UIFixture.today)
        #expect(StatusBarText.icons(calm, lastSaved: nil)[1] == nil, "nothing overdue, no warning")
    }

    @Test func theWindowDraws() throws {
        let model = try UIFixture.model(UIFixture.invoicedLibrary().library)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "window")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func aMessageBoxDraws() throws {
        let model = try UIFixture.model()
        model.confirm(title: "Delete Draft", text: "Delete draft quote Q-0001? Its number won't be used again.",
                      confirm: "Delete") {}
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "message-box")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theUnreadableScreenDraws() throws {
        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "unreadable")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// From a newer Quote Pilot, Quit is the default button: restoring would roll the library back.
    @Test func theNewerVersionScreenDraws() throws {
        let folder = try UIFixture.file("library.json", Data(#"{"format": 99}"#.utf8)).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "unreadable-newer")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// The Mac's own setting (Desktop & Dock → "Double-click a window's title bar to").
    @Test func doubleClickingTheTitleBarFollowsTheMacsSetting() {
        #expect(WindowDragArea.doubleClickAction(nil) == .zoom)
        #expect(WindowDragArea.doubleClickAction("Maximize") == .zoom)
        #expect(WindowDragArea.doubleClickAction("Fill") == .zoom)
        #expect(WindowDragArea.doubleClickAction("Minimize") == .minimize)
        #expect(WindowDragArea.doubleClickAction("None") == .nothing)
    }
}
