import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct ClientsTests {
    @Test func editingAClientSavesIt() throws {
        let model = try UIFixture.sampleModel()
        let id = try #require(model.library.clients.first { $0.name == "Example Bakery" }?.id)
        model.clientBinding(id).wrappedValue.email = "orders@example.com"
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.client(id)?.email == "orders@example.com")
    }

    @Test func aNewQuoteForAClientPicksThatClient() throws {
        let model = try UIFixture.sampleModel()
        let id = try #require(model.library.clients.first?.id)
        model.newQuote(for: id)
        let quoteID = try #require(model.openQuoteID)
        #expect(model.library.quote(quoteID)?.clientID == id)
    }

    @Test func theSummaryAddsUpTheClientsWork() throws {
        let model = try UIFixture.sampleModel()
        let bakery = try #require(model.library.clients.first { $0.name == "Example Bakery" }?.id)
        let summary = ClientSummary(library: model.library, clientID: bakery)
        #expect(summary.quotes == 2)
        #expect(summary.invoiced == Money(dollars: 150))
        #expect(summary.paid == .zero)
        #expect(summary.owing == Money(dollars: 150))
    }

    @Test func theClientsScreenDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .clients
        model.selectedClientID = model.library.clients.first?.id
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "clients")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
