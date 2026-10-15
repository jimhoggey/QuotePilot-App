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
        var beeps = 0
        model.beep = { beeps += 1 }
        for section in [AppSection.quotes, .invoices, .clients, .activity] {
            model.section = section
            let before = model.findRequest
            model.find()
            #expect(model.findRequest == before + 1, "\(section.title) has a Find field")
        }
        #expect(beeps == 0)
    }

    /// The Dashboard, Brand and an open editor have no Find field, so ⌘F has nothing to focus.
    @Test func commandFBeepsWhenNoFindFieldIsOnScreen() throws {
        let model = try UIFixture.sampleModel()
        var beeps = 0
        model.beep = { beeps += 1 }

        model.section = .dashboard
        model.find()
        #expect(beeps == 1)
        model.section = .brand
        model.find()
        #expect(beeps == 2)

        model.openQuote(try #require(model.library.quote(number: "Q-0002")).id)
        model.find()
        #expect(beeps == 3)
        model.openInvoice(try #require(model.library.invoices.first).id)
        model.find()
        #expect(beeps == 4)
        #expect(model.findRequest == 0)

        // Back at the lists, the field is there again.
        model.openInvoiceID = nil
        model.find()
        #expect(model.findRequest == 1)
        // The quote editor is still open on Quotes; its list has the field.
        model.section = .quotes
        model.find()
        #expect(beeps == 5)
        model.openQuoteID = nil
        model.find()
        #expect(model.findRequest == 2)
        #expect(beeps == 5)
    }

    @Test func commandFBeepsOnTheUnreadableScreen() throws {
        let folder = try UIFixture.file("library.json", Data("not a library".utf8)).deletingLastPathComponent()
        let model = try UIFixture.model(folder: folder)
        model.section = .quotes
        var beeps = 0
        model.beep = { beeps += 1 }
        model.find()
        #expect(beeps == 1)
        #expect(model.findRequest == 0)
    }

    // MARK: A hidden row is never selected

    @Test func aSearchThatHidesTheSelectedQuoteClearsTheSelection() throws {
        let model = try UIFixture.sampleModel()
        let draft = try #require(model.library.quote(number: "Q-0004"))
        model.section = .quotes
        model.selectedQuoteID = draft.id
        #expect(model.canExportPDF)

        // Still shown: still selected.
        model.findText[.quotes] = "bakery"
        #expect(model.selectedQuoteID == draft.id)

        // Hidden: nothing is selected, so Open, Duplicate, Delete Draft, ⌘S and Save PDF have nothing to act on.
        model.findText[.quotes] = "Q-0002"
        #expect(!QuoteListView.visibleRows(model).contains { $0.id == draft.id })
        #expect(model.selectedQuoteID == nil)
        #expect(model.sendableDocument == nil)
        #expect(!model.canExportPDF)
    }

    @Test func clearingTheSearchDoesNotBringTheSelectionBack() throws {
        let model = try UIFixture.sampleModel()
        model.section = .quotes
        model.selectedQuoteID = try #require(model.library.quote(number: "Q-0004")).id
        model.findBinding(.quotes).wrappedValue = "Q-0002"
        model.findBinding(.quotes).wrappedValue = ""
        #expect(model.selectedQuoteID == nil)
    }

    @Test func aSearchThatHidesTheSelectedInvoiceOrClientClearsTheSelection() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try #require(model.library.invoices.first { $0.number == "INV-0002" })
        model.section = .invoices
        model.selectedInvoiceID = invoice.id
        model.findText[.invoices] = "overdue"
        #expect(model.selectedInvoiceID == invoice.id)
        model.findText[.invoices] = "INV-0003"
        #expect(model.selectedInvoiceID == nil)
        #expect(model.sendableDocument == nil)
        #expect(!model.canExportPDF)

        let acme = try #require(model.library.clients.first { $0.name == "Acme Test Co" })
        model.selectedClientID = acme.id
        model.findText[.clients] = "acme"
        #expect(model.selectedClientID == acme.id)
        model.findText[.clients] = "bakery"
        #expect(model.selectedClientID == nil)
    }

    /// A search in one list leaves the other lists' selections alone.
    @Test func aSearchOnlyClearsASelectionItHides() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try #require(model.library.invoices.first { $0.number == "INV-0002" })
        model.selectedInvoiceID = invoice.id
        model.findText[.quotes] = "no such quote"
        #expect(model.selectedInvoiceID == invoice.id)
        model.findText[.activity] = "no such entry"
        #expect(model.selectedInvoiceID == invoice.id)
    }

    /// A quote opened from somewhere else (Activity, New Quote, Duplicate) can fall outside the search.
    /// Back at the list it is not left selected there.
    @Test func aQuoteOpenedOutsideTheSearchIsNotLeftSelectedInTheList() throws {
        let model = try UIFixture.sampleModel()
        model.findText[.quotes] = "bakery"
        let other = try #require(model.library.quote(number: "Q-0001"))
        model.openQuote(other.id)
        // The editor shows it, and Save PDF and Send act on the open quote.
        #expect(model.selectedQuoteID == other.id)
        #expect(model.canExportPDF)

        model.go(to: .quotes)
        #expect(model.openQuoteID == nil)
        #expect(model.selectedQuoteID == nil)

        let invoice = try #require(model.library.invoices.first { $0.number == "INV-0003" })
        model.findText[.invoices] = "INV-0002"
        model.openInvoice(invoice.id)
        #expect(model.selectedInvoiceID == invoice.id)
        model.openInvoiceID = nil
        #expect(model.selectedInvoiceID == nil)
    }

    @Test func aFilteredListDraws() throws {
        let model = try UIFixture.sampleModel()
        model.section = .quotes
        model.findText[.quotes] = "bakery"
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quotes-find")
        #expect(rep.map(Snapshot.hasContent) == true)
    }
}
