import Foundation
import Testing
@testable import QuotePilotCore

@Suite struct ClientDeleteTests {
    let today = Fixture.today

    /// The library as it would be saved, to prove a refused delete changed nothing at all.
    func saved(_ library: Library) throws -> Data {
        try Library.makeEncoder().encode(library)
    }

    @Test func anUnusedClientIsDeletedAndLogged() throws {
        var library = Library()
        let keep = Client(name: "Example Bakery")
        let stray = Client(name: "New client")
        library.addClient(keep)
        library.addClient(stray)
        #expect(library.canDeleteClient(stray.id))

        try library.deleteClient(stray.id)

        #expect(library.clients == [keep])
        #expect(library.client(stray.id) == nil)
        #expect(library.activity.first?.message == "Deleted client New client")
        #expect(library.activity.first?.number == nil)
        // The delete is the only new entry: the two adds are still below it.
        #expect(library.activity.count == 3)
    }

    @Test func aClientWithNoNameIsLoggedAsNoName() throws {
        var library = Library()
        let blank = Client(name: "")
        library.addClient(blank)
        try library.deleteClient(blank.id)
        #expect(library.activity.first?.message == "Deleted client (no name)")
    }

    @Test func aClientWithAQuoteStaysEvenWhenTheQuoteIsOnlyADraft() throws {
        var (library, _) = Fixture.libraryWithQuote(stage: .draft)
        let client = try #require(library.clients.first)
        #expect(!library.canDeleteClient(client.id))

        let before = try saved(library)
        #expect(throws: LibraryError.clientInUse(client.name)) { try library.deleteClient(client.id) }
        #expect(try saved(library) == before, "a refused delete changes nothing, not even Activity")
    }

    @Test func aClientWithASentQuoteStays() throws {
        var (library, _) = Fixture.libraryWithQuote(stage: .sent)
        let client = try #require(library.clients.first)
        let before = try saved(library)
        #expect(throws: LibraryError.clientInUse(client.name)) { try library.deleteClient(client.id) }
        #expect(try saved(library) == before)
    }

    @Test func aClientWithAnInvoiceStaysInEveryStage() throws {
        var library = Library()
        let client = Client(name: "Sample Client")
        library.addClient(client)
        let invoice = library.newInvoice(on: today, clientID: client.id)

        // A draft invoice.
        #expect(!library.canDeleteClient(client.id))
        var before = try saved(library)
        #expect(throws: LibraryError.clientInUse("Sample Client")) { try library.deleteClient(client.id) }
        #expect(try saved(library) == before)

        // A sent one.
        try library.markSent(invoice: invoice.id)
        #expect(!library.canDeleteClient(client.id))
        before = try saved(library)
        #expect(throws: LibraryError.clientInUse("Sample Client")) { try library.deleteClient(client.id) }
        #expect(try saved(library) == before)

        // A void one still shows the client on its record.
        try library.voidInvoice(invoice.id)
        #expect(library.invoice(invoice.id)?.stage == .void)
        #expect(!library.canDeleteClient(client.id))
        before = try saved(library)
        #expect(throws: LibraryError.clientInUse("Sample Client")) { try library.deleteClient(client.id) }
        #expect(try saved(library) == before)
    }

    @Test func aClientIsFreeAgainOnceItsLastDraftIsDeleted() throws {
        var library = Library()
        let client = Client(name: "Sample Client")
        library.addClient(client)
        let quote = library.newQuote(on: today, clientID: client.id)
        #expect(!library.canDeleteClient(client.id))

        try library.deleteDraft(quote: quote.id)
        #expect(library.canDeleteClient(client.id))
        try library.deleteClient(client.id)
        #expect(library.clients.isEmpty)
    }

    @Test func onlyThatClientsDocumentsHoldItBack() throws {
        var library = Library()
        let busy = Client(name: "Example Bakery")
        let idle = Client(name: "Acme Traders")
        library.addClient(busy)
        library.addClient(idle)
        library.newQuote(on: today, clientID: busy.id)

        try library.deleteClient(idle.id)
        #expect(library.clients == [busy])
        #expect(library.quotes.count == 1)
    }

    @Test func aClientThatIsntThereCantBeDeleted() throws {
        var library = Library()
        library.addClient(Client(name: "Example Bakery"))
        let before = try saved(library)

        #expect(!library.canDeleteClient(UUID()))
        #expect(throws: LibraryError.notFound) { try library.deleteClient(UUID()) }
        #expect(try saved(library) == before)
    }

    @Test func theRefusalSaysWhoAndWhy() {
        #expect(LibraryError.clientInUse("Sample Client").message
            == "Sample Client has quotes or invoices, so it can't be deleted.")
        #expect(LibraryError.clientInUse("Sample Client").localizedDescription == LibraryError.clientInUse("Sample Client").message)
        // A client with no name yet still gets a sentence that reads properly.
        #expect(LibraryError.clientInUse("").message == "This client has quotes or invoices, so it can't be deleted.")
        #expect(LibraryError.clientInUse("  ").message == "This client has quotes or invoices, so it can't be deleted.")
    }
}
