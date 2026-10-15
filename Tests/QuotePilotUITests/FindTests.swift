import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct FindTests {
    @Test func everyWordHasToMatchSomewhere() {
        let fields = ["Q-0002", "Example Bakery", "Menu boards", "Sent"]
        #expect(Find.matches("", fields))
        #expect(Find.matches("bakery", fields))
        #expect(Find.matches("BAKERY menu", fields))
        #expect(Find.matches("q-0002", fields))
        #expect(!Find.matches("bakery logo", fields))
        #expect(Find.matches("cafe", ["Northside Café"]))
    }

    @Test func eachListFiltersBySearch() throws {
        let model = try UIFixture.sampleModel()
        model.findText[.quotes] = "bakery"
        #expect(QuoteListView.visibleRows(model).map(\.number) == ["Q-0002", "Q-0004"])
        model.findText[.invoices] = "overdue"
        #expect(InvoicesView.visibleRows(model).map(\.number) == ["INV-0002"])
        model.findText[.clients] = "acme"
        #expect(ClientsView.visibleClients(model).map(\.name) == ["Acme Test Co"])
        model.findText[.activity] = "INV-0003"
        #expect(!ActivityView.visibleEntries(model).isEmpty)
        #expect(ActivityView.visibleEntries(model).allSatisfy { $0.number == "INV-0003" || $0.message.contains("INV-0003") })
    }

    @Test func commandFFocusesTheField() throws {
        let model = try UIFixture.sampleModel()
        model.find()
        model.find()
        #expect(model.findRequest == 2)
    }

    @Test func aFilteredListDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .quotes
        model.findText[.quotes] = "bakery"
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quotes-find")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
