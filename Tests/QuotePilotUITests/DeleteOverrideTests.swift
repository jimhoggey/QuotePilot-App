import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// Delete… on a list row's right-click menu. The menu itself can't be clicked in a test, so these
/// call what its item calls.
@MainActor
@Suite struct DeleteOverrideUITests {
    let today = UIFixture.today

    /// A made-up job: Q-0001 accepted 50/50, with the deposit INV-0001 sent and part paid, and the
    /// final INV-0002 drafted; plus a sent quote Q-0002 and a one-off invoice INV-0003 nobody
    /// deducts.
    struct Job {
        var model: AppModel
        var quote: UUID
        var deposit: UUID
        var final: UUID
        var sentQuote: UUID
        var oneOff: UUID
    }

    func job() throws -> Job {
        var (library, quote) = try UIFixture.invoicedLibrary()
        let deposit = try #require(library.invoices.first).id
        try library.markSent(invoice: deposit)
        try library.recordPayment(Payment(date: today, amount: Money(dollars: 100)), toInvoice: deposit)
        let final = try library.draftNextInvoice(forQuote: quote, on: today).id

        var other = library.newQuote(on: today, clientID: library.clients.first?.id)
        other.addLine(LineItem(title: "Audit", rate: Money(dollars: 300)))
        try library.update(other)
        try library.markSent(quote: other.id)

        var oneOff = library.newInvoice(on: today)
        oneOff.lines = [LineItem(title: "Extra", rate: Money(dollars: 50))]
        try library.update(oneOff)
        return Job(model: try UIFixture.model(library), quote: quote, deposit: deposit, final: final,
                   sentQuote: other.id, oneOff: oneOff.id)
    }

    func saved(_ model: AppModel) throws -> Data {
        try Library.makeEncoder().encode(model.library)
    }

    func choice(_ title: String, in model: AppModel) throws -> MessageBox.Choice {
        try #require(model.message?.choices.first { $0.title == title })
    }

    // MARK: The question's words

    @Test func aQuoteWithNoInvoicesIsAskedAboutPlainly() {
        #expect(AppModel.deleteQuoteText(DeletionPreview(number: "Q-0003", invoiceNumbers: [], hasPayments: false))
            == "Delete Q-0003? This can't be undone.")
    }

    @Test func aQuoteWithInvoicesSaysTheyAndTheirPaymentsGoToo() {
        let preview = DeletionPreview(number: "Q-0003", invoiceNumbers: ["INV-0004", "INV-0005"], hasPayments: false)
        #expect(AppModel.deleteQuoteText(preview)
            == "Delete Q-0003 and its invoices INV-0004, INV-0005? Any payments recorded on them go too. This can't be undone.")
        // The same sentence whether or not a payment exists.
        var paid = preview
        paid.hasPayments = true
        #expect(AppModel.deleteQuoteText(paid) == AppModel.deleteQuoteText(preview))
    }

    @Test func aQuoteWithOneInvoiceReadsInTheSingular() {
        let preview = DeletionPreview(number: "Q-0003", invoiceNumbers: ["INV-0004"], hasPayments: true)
        #expect(AppModel.deleteQuoteText(preview)
            == "Delete Q-0003 and its invoice INV-0004? Any payments recorded on it go too. This can't be undone.")
    }

    @Test func anInvoiceMentionsItsPaymentsOnlyWhenItHasSome() {
        #expect(AppModel.deleteInvoiceText(DeletionPreview(number: "INV-0004", invoiceNumbers: [], hasPayments: false))
            == "Delete INV-0004? This can't be undone.")
        #expect(AppModel.deleteInvoiceText(DeletionPreview(number: "INV-0004", invoiceNumbers: [], hasPayments: true))
            == "Delete INV-0004? Its payments go too. This can't be undone.")
    }

    // MARK: Delete… on a quote

    @Test func deletingASentQuoteAsksOnceWithCancelAsTheDefaultThenDeletes() throws {
        let job = try job()
        let model = job.model
        model.openQuote(job.sentQuote)
        let activityBefore = model.library.activity.count

        model.deleteQuote(job.sentQuote)

        // Asked, not yet done.
        let box = try #require(model.message)
        #expect(box.title == "Delete Quote")
        #expect(box.text == "Delete Q-0002? This can't be undone.")
        #expect(box.choices.map(\.title) == ["Delete", "Cancel"])
        #expect(box.choices.first(where: \.isDefault)?.title == "Cancel")
        #expect(model.library.quote(job.sentQuote) != nil)
        #expect(model.library.activity.count == activityBefore)

        model.respond(try choice("Delete", in: model))

        // Done, with no second pop-up; the list is showing, nothing is selected, the status bar says so.
        #expect(model.message == nil)
        #expect(model.library.quote(job.sentQuote) == nil)
        #expect(model.openQuoteID == nil)
        #expect(model.selectedQuoteID == nil)
        #expect(model.section == .quotes)
        #expect(model.statusNote?.text == "Deleted Q-0002")
        #expect(model.library.activity.first?.message == "Deleted quote Q-0002 (sent)")
        #expect(model.library.nextNumber(.quote) == "Q-0003")
        // Saved: the file on disk agrees.
        guard case .loaded(let onDisk) = model.store.load() else {
            Issue.record("Not saved")
            return
        }
        #expect(onDisk.quote(job.sentQuote) == nil)
        #expect(onDisk.activity.first?.message == "Deleted quote Q-0002 (sent)")
    }

    @Test func deletingAQuoteWithInvoicesNamesThemAndTakesThemAndTheirPaymentsToo() throws {
        let job = try job()
        let model = job.model
        model.openInvoice(job.deposit)
        model.selectedQuoteID = job.quote

        model.deleteQuote(job.quote)

        let box = try #require(model.message)
        #expect(box.text
            == "Delete Q-0001 and its invoices INV-0001, INV-0002? Any payments recorded on them go too. This can't be undone.")
        #expect(box.choices.first(where: \.isDefault)?.title == "Cancel")
        #expect(model.library.invoice(job.deposit) != nil, "nothing yet")

        model.respond(try choice("Delete", in: model))

        #expect(model.library.quote(job.quote) == nil)
        #expect(model.library.invoice(job.deposit) == nil)
        #expect(model.library.invoice(job.final) == nil)
        #expect(model.dashboard.receivedThisYear == .zero, "the payment on the deposit went with it")
        // The deposit's editor was open: it is closed, and its row is no longer selected.
        #expect(model.openInvoiceID == nil)
        #expect(model.selectedInvoiceID == nil)
        #expect(model.selectedQuoteID == nil)
        #expect(model.statusNote?.text == "Deleted Q-0001")
        #expect(model.library.activity.first?.message == "Deleted quote Q-0001 (accepted) and invoices INV-0001, INV-0002")
        // What belonged to nothing else is left alone.
        #expect(model.library.quote(job.sentQuote) != nil)
        #expect(model.library.invoice(job.oneOff) != nil)
        #expect(model.library.nextNumber(.invoice) == "INV-0004")
    }

    @Test func deletingAQuoteLeavesOtherSelectionsAndOpenEditorsAlone() throws {
        let job = try job()
        let model = job.model
        model.selectedInvoiceID = job.oneOff
        model.openInvoiceID = job.oneOff
        model.section = .quotes
        model.selectedQuoteID = job.quote

        model.deleteQuote(job.sentQuote)
        model.respond(try choice("Delete", in: model))

        #expect(model.selectedQuoteID == job.quote)
        #expect(model.selectedInvoiceID == job.oneOff)
        #expect(model.openInvoiceID == job.oneOff)
        #expect(model.section == .quotes)
    }

    @Test func cancellingKeepsEverythingAsItWas() throws {
        let job = try job()
        let model = job.model
        model.openQuote(job.quote)
        let before = try saved(model)

        model.deleteQuote(job.quote)
        model.respond(try choice("Cancel", in: model))

        #expect(model.message == nil)
        #expect(try saved(model) == before)
        #expect(model.openQuoteID == job.quote)
        #expect(model.selectedQuoteID == job.quote)
        #expect(model.statusNote == nil)
    }

    @Test func anyStageOfQuoteCanBeDeleted() throws {
        for stage in [QuoteStage.draft, .sent, .accepted, .declined] {
            var library = Library()
            var quote = library.newQuote(on: today)
            quote.stage = stage
            try library.update(quote)
            let model = try UIFixture.model(library)
            model.deleteQuote(quote.id)
            model.respond(try choice("Delete", in: model))
            #expect(model.library.quotes.isEmpty, "\(stage)")
        }
    }

    @Test func deletingTheOpenQuoteReturnsToTheList() throws {
        let job = try job()
        let model = job.model
        model.openQuote(job.sentQuote)
        model.deleteQuote(job.sentQuote)
        model.respond(try choice("Delete", in: model))
        #expect(model.openQuoteID == nil)
        #expect(model.section == .quotes)
        #expect(model.exportableContent == nil, "Save PDF has nothing left to save")
    }

    @Test func deletingAQuoteThatIsntThereDoesNothing() throws {
        let job = try job()
        let model = job.model
        let before = try saved(model)
        model.deleteQuote(UUID())
        #expect(model.message == nil)
        #expect(try saved(model) == before)
    }

    @Test func aFailedSaveKeepsTheQuoteAndSaysWhy() throws {
        let job = try job()
        let model = job.model
        // A file where the library folder should be: the save can't happen.
        try? FileManager.default.removeItem(at: model.store.folder)
        try Data().write(to: model.store.folder)
        let before = try saved(model)
        model.openQuote(job.sentQuote)

        model.deleteQuote(job.sentQuote)
        model.respond(try choice("Delete", in: model))

        let box = try #require(model.message)
        #expect(box.title == "Couldn't delete Q-0002")
        #expect(try saved(model) == before, "a save that failed keeps the app's library as it was")
        #expect(model.library.quote(job.sentQuote) != nil)
        #expect(model.openQuoteID == job.sentQuote)
        #expect(model.statusNote == nil)
        try? FileManager.default.removeItem(at: model.store.folder)
    }

    // MARK: Delete… on an invoice

    @Test func deletingAnInvoiceWithPaymentsSaysSoAndDeletesIt() throws {
        let job = try job()
        let model = job.model
        model.openInvoice(job.final)
        // The final deducts the deposit (which has the payment), so it goes first.
        model.deleteInvoice(job.final)
        model.respond(try choice("Delete", in: model))
        #expect(model.openInvoiceID == nil)
        #expect(model.selectedInvoiceID == nil)

        model.openInvoice(job.deposit)
        model.deleteInvoice(job.deposit)

        let box = try #require(model.message)
        #expect(box.title == "Delete Invoice")
        #expect(box.text == "Delete INV-0001? Its payments go too. This can't be undone.")
        #expect(box.choices.map(\.title) == ["Delete", "Cancel"])
        #expect(box.choices.first(where: \.isDefault)?.title == "Cancel")
        #expect(model.library.invoice(job.deposit) != nil)

        model.respond(try choice("Delete", in: model))

        #expect(model.message == nil)
        #expect(model.library.invoice(job.deposit) == nil)
        #expect(model.openInvoiceID == nil)
        #expect(model.selectedInvoiceID == nil)
        #expect(model.section == .invoices, "stays on the Invoices list")
        #expect(model.statusNote?.text == "Deleted INV-0001")
        #expect(model.library.activity.first?.message == "Deleted invoice INV-0001 (sent)")
        #expect(model.dashboard.receivedThisYear == .zero)
        #expect(model.library.quote(job.quote) != nil, "its quote stays")
        #expect(model.library.nextNumber(.invoice) == "INV-0004")
    }

    @Test func anInvoiceWithNoPaymentsIsAskedAboutPlainly() throws {
        let job = try job()
        let model = job.model
        model.selectedInvoiceID = job.oneOff

        model.deleteInvoice(job.oneOff)

        #expect(model.message?.text == "Delete INV-0003? This can't be undone.")
        model.respond(try choice("Delete", in: model))
        #expect(model.library.invoice(job.oneOff) == nil)
        #expect(model.selectedInvoiceID == nil)
        #expect(model.library.activity.first?.message == "Deleted invoice INV-0003 (draft)")
    }

    @Test func cancellingAnInvoiceDeleteKeepsItAndItsSelection() throws {
        let job = try job()
        let model = job.model
        model.selectedInvoiceID = job.oneOff
        let before = try saved(model)

        model.deleteInvoice(job.oneOff)
        model.respond(try choice("Cancel", in: model))

        #expect(try saved(model) == before)
        #expect(model.selectedInvoiceID == job.oneOff)
        #expect(model.statusNote == nil)
    }

    @Test func aDepositTheFinalStillDeductsSaysWhyInsteadOfAsking() throws {
        let job = try job()
        let model = job.model
        model.selectedInvoiceID = job.deposit
        let before = try saved(model)

        model.deleteInvoice(job.deposit)

        let box = try #require(model.message)
        #expect(box.title == "Can't Delete")
        #expect(box.text == "INV-0002 deducts this deposit. Delete INV-0002 first.")
        #expect(box.choices.map(\.title) == ["OK"], "the question is never asked only to be refused")
        #expect(try saved(model) == before)
        #expect(model.selectedInvoiceID == job.deposit)
        #expect(model.statusNote == nil)
    }

    @Test func theDepositCanGoOnceTheFinalIsGone() throws {
        let job = try job()
        let model = job.model
        model.deleteInvoice(job.final)
        model.respond(try choice("Delete", in: model))
        model.deleteInvoice(job.deposit)
        #expect(model.message?.title == "Delete Invoice", "asked now, not refused")
        model.respond(try choice("Delete", in: model))
        #expect(model.library.invoice(job.deposit) == nil)
    }

    @Test func deletingAnInvoiceThatIsntThereDoesNothing() throws {
        let job = try job()
        let model = job.model
        let before = try saved(model)
        model.deleteInvoice(UUID())
        #expect(model.message == nil)
        #expect(try saved(model) == before)
    }

    // MARK: Waiting for a free window

    /// A command waits while a message box (or any dialog or panel) is up, so Delete… can never replace
    /// an unread message, and a second press can't stack a second question on the first.
    @Test func deletingWaitsWhileAMessageOrDialogIsUp() throws {
        let job = try job()
        let model = job.model
        var beeps = 0
        model.beep = { beeps += 1 }

        model.deleteQuote(job.sentQuote)
        let asked = try #require(model.message)
        model.deleteQuote(job.sentQuote)
        model.deleteInvoice(job.oneOff)
        #expect(beeps == 2)
        #expect(model.message?.id == asked.id)

        model.message = nil
        model.dialog = .taxExport
        model.deleteQuote(job.sentQuote)
        model.deleteInvoice(job.oneOff)
        #expect(beeps == 4)
        #expect(model.message == nil)
        #expect(model.library.quote(job.sentQuote) != nil)
        #expect(model.library.invoice(job.oneOff) != nil)
    }

    // MARK: The right-click menu

    @Test func aRightClickOrControlClickOpensTheMenu() {
        #expect(SelectOnRightClick.opensMenu(.rightMouseDown, modifiers: []))
        #expect(SelectOnRightClick.opensMenu(.leftMouseDown, modifiers: [.control]))
        #expect(!SelectOnRightClick.opensMenu(.leftMouseDown, modifiers: []))
        #expect(!SelectOnRightClick.opensMenu(.leftMouseDown, modifiers: [.command]))
        #expect(!SelectOnRightClick.opensMenu(.rightMouseUp, modifiers: []))
        #expect(!SelectOnRightClick.opensMenu(.otherMouseDown, modifiers: []))
    }

    @Test func theListsDrawWithTheirRowMenus() throws {
        let job = try job()
        for (section, name) in [(AppSection.quotes, "quotes"), (.invoices, "invoices")] {
            job.model.section = section
            let rep = Snapshot.render(RootView(model: job.model), size: CGSize(width: 1240, height: 800), name: "delete-\(name)")
            #expect(rep.map(Snapshot.hasContent) == true, "\(name)")
        }
    }
}
