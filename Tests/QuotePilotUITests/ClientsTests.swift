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

    // MARK: Delete Client

    static let inUseHelp = "Clients with quotes or invoices can't be deleted"

    /// A model holding the sample business plus one stray "New client" nobody has been quoted under.
    func modelWithAStray() throws -> (model: AppModel, stray: UUID) {
        let model = try UIFixture.sampleModel()
        model.newClient()
        let stray = try #require(model.selectedClientID)
        #expect(model.library.client(stray)?.name == "New client")
        return (model, stray)
    }

    @Test func theButtonIsGreyedOutWithNothingSelected() throws {
        let model = try UIFixture.sampleModel()
        #expect(model.selectedClientID == nil)
        #expect(!model.canDeleteClient)
        #expect(model.deleteClientHelp == "Select a client first")
    }

    @Test func theButtonIsOnForAClientWithNoQuotesOrInvoices() throws {
        let (model, _) = try modelWithAStray()
        #expect(model.canDeleteClient)
        #expect(model.deleteClientHelp == "Delete the selected client")
    }

    @Test func theButtonIsGreyedOutForAClientWithAQuote() throws {
        let model = try UIFixture.sampleModel()
        model.selectedClientID = try #require(model.library.clients.first { $0.name == "Example Bakery" }?.id)
        #expect(!model.canDeleteClient)
        #expect(model.deleteClientHelp == Self.inUseHelp)
    }

    /// A draft quote, a draft invoice and a void invoice each hold their client.
    @Test func theButtonIsGreyedOutForADraftOrVoidDocumentsClient() throws {
        var library = Library()
        let quoted = Client(name: "Quoted Co"), invoiced = Client(name: "Invoiced Co"), voided = Client(name: "Voided Co")
        for client in [quoted, invoiced, voided] { library.addClient(client) }
        library.newQuote(on: UIFixture.today, clientID: quoted.id)
        library.newInvoice(on: UIFixture.today, clientID: invoiced.id)
        let old = library.newInvoice(on: UIFixture.today, clientID: voided.id)
        try library.markSent(invoice: old.id)
        try library.voidInvoice(old.id)
        let model = try UIFixture.model(library)

        for client in [quoted, invoiced, voided] {
            model.selectedClientID = client.id
            #expect(!model.canDeleteClient, "\(client.name)")
            #expect(model.deleteClientHelp == Self.inUseHelp, "\(client.name)")
        }
    }

    @Test func theButtonIsGreyedOutWhenTheLibraryCantBeRead() throws {
        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        #expect(model.loadState != .ready)
        model.selectedClientID = UUID()
        #expect(!model.canDeleteClient)
    }

    @Test func aGreyedOutButtonDoesNothingEvenIfPressed() throws {
        let model = try UIFixture.sampleModel()
        var beeps = 0
        model.beep = { beeps += 1 }
        let before = model.library.clients
        let bakery = try #require(model.library.clients.first { $0.name == "Example Bakery" }?.id)

        model.deleteSelectedClient()
        model.selectedClientID = bakery
        model.deleteSelectedClient()

        #expect(model.message == nil, "the menu or key never explains in a box; the button was grey")
        #expect(model.library.clients == before)
        #expect(beeps == 2)
    }

    @Test func deletingAsksOnceWithCancelAsTheDefaultThenDeletes() throws {
        let (model, stray) = try modelWithAStray()
        let others = model.library.clients.filter { $0.id != stray }
        let activityBefore = model.library.activity.count

        model.deleteSelectedClient()

        // Asked, not yet done.
        let box = try #require(model.message)
        #expect(box.title == "Delete Client")
        #expect(box.text == "Delete New client? This can't be undone.")
        #expect(box.choices.map(\.title) == ["Delete", "Cancel"])
        #expect(box.choices.first(where: \.isDefault)?.title == "Cancel")
        #expect(model.library.client(stray) != nil)
        #expect(model.library.activity.count == activityBefore)

        model.respond(try #require(box.choices.first { $0.title == "Delete" }))

        // Done, with no second pop-up: the client is gone, nothing is selected, the form is closed.
        #expect(model.message == nil)
        #expect(model.library.client(stray) == nil)
        #expect(model.library.clients == others)
        #expect(model.selectedClientID == nil)
        #expect(!model.canDeleteClient)
        #expect(model.deleteClientHelp == "Select a client first")
        #expect(model.library.activity.first?.message == "Deleted client New client")
        // Saved: the file on disk agrees.
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.client(stray) == nil)
        #expect(saved.activity.first?.message == "Deleted client New client")
    }

    @Test func cancellingKeepsTheClientAndTheSelection() throws {
        let (model, stray) = try modelWithAStray()
        let before = model.library.clients
        let activityBefore = model.library.activity.count

        model.deleteSelectedClient()
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first { $0.title == "Cancel" }))

        #expect(model.message == nil)
        #expect(model.library.clients == before)
        #expect(model.library.activity.count == activityBefore)
        #expect(model.selectedClientID == stray)
        #expect(model.canDeleteClient)
    }

    @Test func aBlankNamedClientIsAskedAboutPlainly() throws {
        let (model, stray) = try modelWithAStray()
        var client = try #require(model.library.client(stray))
        client.name = ""
        model.updateClient(client)

        model.deleteSelectedClient()

        #expect(model.message?.text == "Delete this client? This can't be undone.")
        model.respond(try #require(model.message?.choices.first { $0.title == "Delete" }))
        #expect(model.library.client(stray) == nil)
        #expect(model.library.activity.first?.message == "Deleted client (no name)")
    }

    /// A command waits while a message box (or any dialog or panel) is up, so Delete Client can never
    /// replace an unread message, and a second press can't stack a second question on the first.
    @Test func deletingWaitsWhileAMessageIsUp() throws {
        let (model, stray) = try modelWithAStray()
        var beeps = 0
        model.beep = { beeps += 1 }

        model.deleteSelectedClient()
        let asked = try #require(model.message)
        model.deleteSelectedClient()
        #expect(beeps == 1)
        #expect(model.message?.id == asked.id)
        #expect(model.library.client(stray) != nil)

        model.message = nil
        model.dialog = .taxExport
        model.deleteSelectedClient()
        #expect(beeps == 2)
        #expect(model.message == nil)
        #expect(model.library.client(stray) != nil)
    }

    // MARK: Delete Client with Find

    /// A rename that stops matching the search leaves the form open (by design, so it doesn't vanish
    /// under the cursor), but the list no longer shows that client, so the button leaves them alone.
    @Test func aSelectedClientTheSearchHidesIsNotDeleted() throws {
        let (model, stray) = try modelWithAStray()
        model.findText[.clients] = "new"
        #expect(model.selectedClientID == stray, "still matches, so still selected")
        #expect(model.canDeleteClient)

        var client = try #require(model.library.client(stray))
        client.name = "Renamed Co"
        model.updateClient(client)
        #expect(model.selectedClientID == stray, "the form stays open under the cursor")
        #expect(!ClientsView.visibleClients(model).contains { $0.id == stray })
        #expect(!model.canDeleteClient)
        #expect(model.deleteClientHelp == "Clear the search to delete this client")

        var beeps = 0
        model.beep = { beeps += 1 }
        model.deleteSelectedClient()
        #expect(model.message == nil)
        #expect(beeps == 1)
        #expect(model.library.client(stray) != nil)

        // Clearing the search brings the row, and the button, back.
        model.findText[.clients] = ""
        #expect(model.selectedClientID == stray)
        #expect(model.canDeleteClient)
        model.deleteSelectedClient()
        model.respond(try #require(model.message?.choices.first { $0.title == "Delete" }))
        #expect(model.library.client(stray) == nil)
        #expect(model.selectedClientID == nil)
    }

    /// Typing a search that hides the selected client clears the selection, which greys the button.
    @Test func searchingAwayTheSelectedClientGreysOutTheButton() throws {
        let (model, _) = try modelWithAStray()
        #expect(model.canDeleteClient)
        model.findText[.clients] = "bakery"
        #expect(model.selectedClientID == nil)
        #expect(!model.canDeleteClient)
        #expect(model.deleteClientHelp == "Select a client first")
    }

    /// New Client under a search that hides "New client" selects a row the list doesn't show.
    @Test func aNewClientHiddenByTheSearchCantBeDeletedUntilTheSearchIsCleared() throws {
        let model = try UIFixture.sampleModel()
        model.findText[.clients] = "bakery"
        model.newClient()
        let stray = try #require(model.selectedClientID)
        #expect(!ClientsView.visibleClients(model).contains { $0.id == stray })
        #expect(!model.canDeleteClient)

        model.findText[.clients] = ""
        #expect(model.selectedClientID == stray)
        #expect(model.canDeleteClient)
    }

    @Test func deletingAClientLeavesFindAndTheOtherSelectionsAlone() throws {
        let (model, stray) = try modelWithAStray()
        model.section = .quotes
        let quote = try #require(model.library.quotes.first { $0.clientID != nil })
        model.selectedQuoteID = quote.id
        model.findText[.quotes] = ""
        model.findText[.activity] = "quote"
        let sendable = try #require(model.sendableDocument)

        model.section = .clients
        model.selectedClientID = stray
        model.deleteSelectedClient()
        model.respond(try #require(model.message?.choices.first { $0.title == "Delete" }))

        #expect(model.selectedQuoteID == quote.id)
        #expect(model.findText[.activity] == "quote")
        #expect(model.findText[.clients, default: ""] == "")
        model.section = .quotes
        #expect(model.sendableDocument == sendable)
    }

    @Test func theClientsScreenDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .clients
        model.selectedClientID = model.library.clients.first?.id
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "clients")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
