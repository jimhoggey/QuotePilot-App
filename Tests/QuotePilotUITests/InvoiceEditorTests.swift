import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct InvoiceEditorTests {
    func invoice(_ model: AppModel, _ number: String) throws -> Invoice {
        try #require(model.library.invoices.first { $0.number == number })
    }

    @Test func aNewInvoiceOpensInTheEditor() throws {
        let model = try UIFixture.sampleModel()
        model.newInvoice()
        let id = try #require(model.openInvoiceID)
        #expect(model.section == .invoices)
        #expect(model.library.invoice(id)?.kind == .standalone)
        #expect(model.library.invoice(id)?.number == "INV-0004")
    }

    @Test func editingADraftSavesIt() throws {
        let model = try UIFixture.sampleModel()
        model.newInvoice()
        let id = try #require(model.openInvoiceID)
        model.invoiceBinding(id).wrappedValue.lines = [LineItem(title: "Extra page", rate: Money(dollars: 250))]
        guard case .loaded(let saved) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(saved.invoice(id)?.amount == Money(dollars: 250))
    }

    @Test func aSentInvoiceStaysAsItWas() throws {
        let model = try UIFixture.sampleModel()
        let care = try invoice(model, "INV-0002")
        model.invoiceBinding(care.id).wrappedValue.title = "Changed"
        #expect(model.library.invoice(care.id) == care)
        #expect(model.message?.text == LibraryError.notEditable.message)
    }

    @Test func draftInvoiceNowDraftsTheBalance() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0001"))
        model.draftInvoiceNow(forQuote: quote.id)
        let id = try #require(model.openInvoiceID)
        let final = try #require(model.library.invoice(id))
        #expect(final.kind == .final)
        #expect(final.amount == Money(dollars: 1935))
    }

    @Test func jobCompleteDraftsTheClosingInvoiceOnce() throws {
        let model = try UIFixture.sampleModel()
        let quote = try #require(model.library.quote(number: "Q-0001"))
        model.completeJob(quote.id)
        #expect(model.library.quote(quote.id)?.completedOn == UIFixture.today)
        let closing = try #require(model.openInvoiceID)
        #expect(model.library.invoice(closing)?.kind == .final)
        let count = model.library.invoices.count
        // Again, from somewhere else: no second invoice, no message box, and the closing invoice opens.
        model.openInvoiceID = nil
        model.section = .quotes
        model.completeJob(quote.id)
        #expect(model.library.invoices.count == count)
        #expect(model.message == nil)
        #expect(model.openInvoiceID == closing)
        #expect(model.section == .invoices)
    }

    @Test func jobCompleteOnAFullAmountQuoteOpensItsFullInvoice() throws {
        var library = Library()
        let client = Client(name: "Sample Client Pty Ltd")
        library.addClient(client)
        var quote = library.newQuote(on: UIFixture.today, clientID: client.id)
        quote.plan = .fullAmount
        quote.addLine(LineItem(title: "Design", rate: Money(dollars: 600)))
        try library.update(quote)
        try library.markSent(quote: quote.id)
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01"], declined: []), forQuote: quote.id)
        let full = try library.draftNextInvoice(forQuote: quote.id, on: UIFixture.today)
        let model = try UIFixture.model(library)
        model.completeJob(quote.id)
        #expect(model.message == nil)
        #expect(model.openInvoiceID == full.id)
        #expect(model.library.quote(quote.id)?.completedOn == UIFixture.today)
    }

    @Test func voidingAsksFirst() throws {
        let model = try UIFixture.sampleModel()
        let care = try invoice(model, "INV-0002")
        model.voidInvoice(care.id)
        #expect(model.library.invoice(care.id)?.stage == .sent)
        let box = try #require(model.message)
        model.respond(try #require(box.choices.first { $0.title == "Void" }))
        #expect(model.library.invoice(care.id)?.stage == .void)
    }

    @Test func onlyOneOffInvoicesCanBeDuplicated() throws {
        let model = try UIFixture.sampleModel()
        let deposit = try invoice(model, "INV-0001")
        model.duplicateInvoice(deposit.id)
        #expect(model.message?.title == "Can't Duplicate")
        model.message = nil
        let care = try invoice(model, "INV-0002")
        model.duplicateInvoice(care.id)
        let copy = try #require(model.openInvoiceID.flatMap { model.library.invoice($0) })
        #expect(copy.kind == .standalone)
        #expect(copy.stage == .draft)
        #expect(copy.amount == care.amount)
    }

    @Test func deletingADraftInvoiceAsksFirst() throws {
        let model = try UIFixture.sampleModel()
        model.newInvoice()
        let id = try #require(model.openInvoiceID)
        model.deleteDraftInvoice(id)
        model.respond(try #require(model.message?.choices.first { $0.title == "Delete" }))
        #expect(model.library.invoice(id) == nil)
        #expect(model.openInvoiceID == nil)
    }

    @Test func theInvoiceEditorDraws() throws {
        let model = try UIFixture.sampleModel()
        model.openInvoice(try invoice(model, "INV-0003").id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "invoice-editor")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    @Test func theQuoteEditorShowsItsInvoiceActions() throws {
        let model = try UIFixture.sampleModel()
        model.openQuote(try #require(model.library.quote(number: "Q-0001")).id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "quote-editor-actions")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    // MARK: Beyond the ten above: the rest of what this task changes

    @Test func chooseInvoicesAgainGoesBackToTheList() throws {
        let model = try UIFixture.sampleModel()
        model.openInvoice(try invoice(model, "INV-0003").id)
        #expect(model.openInvoiceID != nil)
        model.go(to: .invoices)
        #expect(model.openInvoiceID == nil)
        #expect(model.section == .invoices)
        // Coming from another section keeps the open invoice, as Quotes does.
        model.openInvoice(try invoice(model, "INV-0003").id)
        model.go(to: .dashboard)
        model.go(to: .invoices)
        #expect(model.openInvoiceID != nil)
    }

    @Test func savingAndSendingUseTheOpenInvoice() throws {
        let model = try UIFixture.sampleModel()
        let care = try invoice(model, "INV-0002")
        let hosting = try invoice(model, "INV-0003")
        model.openInvoice(hosting.id)
        model.selectedInvoiceID = care.id
        #expect(model.sendableDocument == .invoice(hosting.id))
        #expect(model.exportableContent?.fileName.contains("INV-0003") == true)
        // Without an open invoice the selected one is used, as before.
        model.openInvoiceID = nil
        #expect(model.sendableDocument == .invoice(care.id))
        #expect(model.exportableContent?.fileName.contains("INV-0002") == true)
    }

    @Test func aDraftInvoiceIsNotYetOwed() throws {
        let model = try UIFixture.sampleModel()
        model.newInvoice()
        let id = try #require(model.openInvoiceID)
        model.invoiceBinding(id).wrappedValue.lines = [LineItem(title: "Extra page", rate: Money(dollars: 250))]
        let row = InvoiceRow(try #require(model.library.invoice(id)), library: model.library, today: model.today)
        #expect(row.status == .draft)
        #expect(row.amount == Money(dollars: 250))
        #expect(row.owing == .zero)
    }

    @Test func aDeletedOpenInvoiceFallsBackToTheList() throws {
        let model = try UIFixture.sampleModel()
        model.newInvoice()
        let id = try #require(model.openInvoiceID)
        // The invoice is gone from the library, so the screen shows the list rather than an empty editor.
        model.deleteDraftInvoice(id)
        model.respond(try #require(model.message?.choices.first { $0.title == "Delete" }))
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "invoices-after-delete")
        #expect(rep.map(Snapshot.hasContent) == true)
        #expect(model.openInvoiceID == nil)
    }

    @Test func aLineIsNamedWithoutItsCodeWhenTheDocumentShowsNone() {
        var line = LineItem(code: "02", title: "Hosting", rate: .zero)
        #expect(LinesEditor<EmptyView>.lineName(line) == "line 02, Hosting")
        #expect(LinesEditor<EmptyView>.lineName(line, showCode: false) == "\"Hosting\"")
        line.title = ""
        #expect(LinesEditor<EmptyView>.lineName(line) == "line 02")
        #expect(LinesEditor<EmptyView>.lineName(line, showCode: false) == "this line")
        line.code = ""
        #expect(LinesEditor<EmptyView>.lineName(line) == "this line")
    }

    // MARK: Removing a line

    @Test func anEmptyLineGoesWithoutAskingAndAFilledOneAsks() throws {
        let model = try UIFixture.sampleModel()
        var lines = [LineItem(title: "", rate: .zero), LineItem(title: "Design", rate: Money(dollars: 600))]
        let editor = LinesEditor(model: model, lines: Binding(get: { lines }, set: { lines = $0 }),
                                 onAdd: {}) { EmptyView() }
        editor.remove(lines[0])
        #expect(model.message == nil)
        #expect(lines.map(\.title) == ["Design"])
        editor.remove(lines[0])
        #expect(lines.count == 1, "a filled line stays until the question is answered")
        let box = try #require(model.message)
        #expect(box.title == "Remove Line")
        model.respond(try #require(box.choices.first { $0.title == "Remove" }))
        #expect(lines.isEmpty)
    }

    @Test func aLineHasContentWhenItHasWordingADetailOrAPrice() {
        #expect(!LinesEditor<EmptyView>.hasContent(LineItem(title: "", rate: .zero)))
        // Spaces alone are nothing, and so is a quantity or unit with nothing to bill.
        #expect(!LinesEditor<EmptyView>.hasContent(LineItem(title: "  ", detail: " \n", quantity: 5, unit: .hours, rate: .zero)))
        #expect(LinesEditor<EmptyView>.hasContent(LineItem(title: "Design", rate: .zero)))
        #expect(LinesEditor<EmptyView>.hasContent(LineItem(title: "", detail: "Two rounds", rate: .zero)))
        #expect(LinesEditor<EmptyView>.hasContent(LineItem(title: "", rate: Money(dollars: 1))))
    }
}
