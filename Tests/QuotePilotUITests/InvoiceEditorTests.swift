import AppKit
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

    /// An open invoice that is no longer in the library (a restored backup, say) must not leave the
    /// screen on an empty editor: the list shows, and the selected invoice still saves and sends.
    @Test func aDeletedOpenInvoiceFallsBackToTheList() throws {
        let model = try UIFixture.sampleModel()
        let care = try invoice(model, "INV-0002")
        model.section = .invoices
        model.selectedInvoiceID = care.id
        model.openInvoiceID = UUID()
        #expect(model.library.invoice(try #require(model.openInvoiceID)) == nil)
        #expect(model.editingInvoiceID == nil)
        #expect(model.sendableDocument == .invoice(care.id))
        #expect(model.exportableContent?.fileName.contains("INV-0002") == true)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "invoices-after-delete")
        #expect(rep.map(Snapshot.hasContent) == true)
        // A real invoice does open.
        model.openInvoiceID = care.id
        #expect(model.editingInvoiceID == care.id)
    }

    @Test func aLineIsNamedWithoutItsCodeWhenTheDocumentShowsNone() {
        var line = LineItem(code: "02", title: "Hosting", rate: .zero)
        #expect(line.removalName() == "line 02, Hosting")
        #expect(line.removalName(showCode: false) == "\"Hosting\"")
        line.title = ""
        #expect(line.removalName() == "line 02")
        #expect(line.removalName(showCode: false) == "this line")
        line.code = ""
        #expect(line.removalName() == "this line")
    }

    @Test func aLineIsLabelledForVoiceOverByItsCodeOrItsPosition() {
        var line = LineItem(code: "02", title: "Hosting", rate: .zero)
        #expect(line.accessibilityName(position: 5, showCode: true) == "02")
        // An invoice shows no codes, so what VoiceOver says is the place the person sees it in.
        #expect(line.accessibilityName(position: 5, showCode: false) == "5")
        line.code = ""
        #expect(line.accessibilityName(position: 2, showCode: true) == "2")
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
        #expect(!LineItem(title: "", rate: .zero).hasContent)
        // Spaces alone are nothing, and so is a quantity or unit with nothing to bill.
        #expect(!LineItem(title: "  ", detail: " \n", quantity: 5, unit: .hours, rate: .zero).hasContent)
        #expect(LineItem(title: "Design", rate: .zero).hasContent)
        #expect(LineItem(title: "", detail: "Two rounds", rate: .zero).hasContent)
        #expect(LineItem(title: "", rate: Money(dollars: 1)).hasContent)
    }

    // MARK: Job Complete stays until the job is complete

    @Test func jobCompleteStaysAvailableAfterTheFinalIsDraftedUntilTheJobIsComplete() throws {
        let model = try UIFixture.sampleModel()
        let q1 = try #require(model.library.quote(number: "Q-0001")).id
        #expect(model.canCompleteJob(q1))
        #expect(model.library.nextInvoiceKind(forQuote: q1) == .final)
        model.draftInvoiceNow(forQuote: q1)
        // Draft Invoice Now has nothing left to draft, but the job still isn't marked complete.
        #expect(model.library.nextInvoiceKind(forQuote: q1) == nil)
        #expect(model.canCompleteJob(q1))
        model.completeJob(q1)
        #expect(model.library.quote(q1)?.completedOn == UIFixture.today)
        #expect(!model.canCompleteJob(q1))
        #expect(model.message == nil)
    }

    @Test func jobCompleteIsOnlyForAnAcceptedQuote() throws {
        let model = try UIFixture.sampleModel()
        #expect(!model.canCompleteJob(try #require(model.library.quote(number: "Q-0002")).id), "sent, not accepted")
        #expect(!model.canCompleteJob(try #require(model.library.quote(number: "Q-0004")).id), "a draft")
        #expect(!model.canCompleteJob(UUID()), "no such quote")
    }

    // MARK: A deposit the final invoice deducts

    /// A 50/50 quote's deposit (INV-0001), then its final (INV-0002), which deducts the deposit.
    func deductedDeposit(sent: Bool = false, paid: Bool = false, finalPaid: Bool = false)
        throws -> (model: AppModel, deposit: UUID, final: Invoice) {
        var (library, quoteID) = try UIFixture.invoicedLibrary()
        let deposit = try #require(library.invoices.first).id
        if sent { try library.markSent(invoice: deposit) }
        if paid { try library.recordPayment(Payment(date: UIFixture.today, amount: Money(dollars: 100)), toInvoice: deposit) }
        let final = try library.draftNextInvoice(forQuote: quoteID, on: UIFixture.today)
        if finalPaid {
            // A final invoice with a payment is sent, and can't be voided until the payment is removed.
            try library.markSent(invoice: final.id)
            try library.recordPayment(Payment(date: UIFixture.today, amount: Money(dollars: 50)), toInvoice: final.id)
        }
        return (try UIFixture.model(library), deposit, final)
    }

    /// When the final invoice has payments, "void or delete it first" can't be done as it stands: the
    /// note and the Void/Delete tooltips say to remove its payments, then void it.
    @Test func aFinalWithPaymentsSaysToRemoveThemThenVoid() throws {
        let (model, deposit, final) = try deductedDeposit(finalPaid: true)
        let rules = try #require(model.invoiceRules(deposit))
        #expect(rules.finalDeducting?.id == final.id)
        #expect(rules.note?.text == "Final invoice INV-0002 deducts this deposit, so its lines, GST and terms can't be changed. Remove INV-0002's payments, then void it.")
        #expect(rules.deductedHelp == "Final invoice INV-0002 deducts this deposit. Remove INV-0002's payments, then void it.")

        let (sentModel, sentDeposit, _) = try deductedDeposit(sent: true, finalPaid: true)
        let sentRules = try #require(sentModel.invoiceRules(sentDeposit))
        #expect(sentRules.note?.text == "This invoice has been sent, so it can't be changed. Final invoice INV-0002 deducts it, so remove INV-0002's payments and void INV-0002 before voiding this one.")
        #expect(sentRules.deductedHelp == "Final invoice INV-0002 deducts this deposit. Remove INV-0002's payments, then void it.")

        // Without payments on the final the wording is as it was, in the note and the tooltips.
        let (plainModel, plainDeposit, _) = try deductedDeposit()
        let plain = try #require(plainModel.invoiceRules(plainDeposit))
        #expect(plain.deductedHelp == "Final invoice INV-0002 deducts this deposit. Void or delete INV-0002 first.")
        // An invoice nothing deducts has no such tooltip.
        #expect(rulesFor(try UIFixture.sampleModel(), "INV-0002").deductedHelp == nil)
    }

    @Test func aDraftDepositTheFinalDeductsIsLocked() throws {
        let (model, deposit, final) = try deductedDeposit()
        #expect(model.library.finalDeducting(deposit)?.id == final.id)
        let rules = try #require(model.invoiceRules(deposit))
        #expect(rules.finalDeducting?.id == final.id)
        #expect(rules.canEditDetails, "title and dates may still change, as core allows")
        #expect(!rules.canEditAmounts, "lines, GST and terms are locked")
        #expect(!rules.canDelete)
        #expect(!rules.canVoid)
        #expect(rules.note?.text == "Final invoice INV-0002 deducts this deposit, so its lines, GST and terms can't be changed. Void or delete INV-0002 first.")
        #expect(rules.note?.warning == false)
    }

    @Test func aSentDepositTheFinalDeductsCantBeVoidedAndSaysWhy() throws {
        let (model, deposit, _) = try deductedDeposit(sent: true)
        let rules = try #require(model.invoiceRules(deposit))
        #expect(!rules.canEditDetails)
        #expect(!rules.canVoid)
        #expect(rules.note?.text == "This invoice has been sent, so it can't be changed. Final invoice INV-0002 deducts it, so void or delete INV-0002 before voiding this one.")
    }

    @Test func theNoteFollowsTheInvoicesState() throws {
        // Sent and unpaid: it can be voided.
        let sample = try UIFixture.sampleModel()
        let care = rulesFor(sample, "INV-0002")
        #expect(care.canVoid)
        #expect(care.note?.text == "This invoice has been sent, so it can't be changed. If something's wrong, void it and draft a new one.")
        // Sent with payments: voiding is off, and the note doesn't suggest it.
        let hosting = rulesFor(sample, "INV-0003")
        #expect(!hosting.canVoid)
        #expect(hosting.note?.text == "This invoice has been sent and has payments recorded, so it can't be changed or voided. Remove the payments first if you need to void it.")
        // A deducted deposit with payments says the payments first: they are what stops voiding.
        let (paidModel, paidDeposit, _) = try deductedDeposit(sent: true, paid: true)
        #expect(try #require(paidModel.invoiceRules(paidDeposit)).note?.text == hosting.note?.text)
        // Void.
        sample.voidInvoice(try invoice(sample, "INV-0002").id)
        sample.respond(try #require(sample.message?.choices.first { $0.title == "Void" }))
        let voided = rulesFor(sample, "INV-0002")
        #expect(!voided.canVoid)
        #expect(!voided.canEditDetails)
        #expect(voided.note == InvoiceRules.Note(text: "This invoice is void. It no longer counts as owed, and its number stays used.", warning: true))
        // A new draft has no note and everything open.
        sample.newInvoice()
        let fresh = try #require(sample.openInvoiceID.flatMap { sample.invoiceRules($0) })
        #expect(fresh.note == nil)
        #expect(fresh.canEditDetails && fresh.canEditAmounts && fresh.canDelete)
        #expect(!fresh.canVoid)
    }

    func rulesFor(_ model: AppModel, _ number: String) -> InvoiceRules {
        let id = model.library.invoices.first { $0.number == number }!.id
        return model.invoiceRules(id)!
    }

    @Test func voidingOrDeletingADepositTheFinalDeductsAsksNothingAndSaysWhyOnce() throws {
        let (sentModel, sentDeposit, _) = try deductedDeposit(sent: true)
        sentModel.voidInvoice(sentDeposit)
        let box = try #require(sentModel.message)
        #expect(box.title == "Can't Void")
        #expect(box.text == LibraryError.deductedByFinal("INV-0002").message)
        #expect(box.choices.count == 1, "one OK button, not a question that is then refused")
        #expect(sentModel.library.invoice(sentDeposit)?.stage == .sent)

        let (draftModel, draftDeposit, _) = try deductedDeposit()
        draftModel.deleteDraftInvoice(draftDeposit)
        let deleteBox = try #require(draftModel.message)
        #expect(deleteBox.title == "Can't Delete")
        #expect(deleteBox.text == LibraryError.deductedByFinal("INV-0002").message)
        #expect(deleteBox.choices.count == 1)
        #expect(draftModel.library.invoice(draftDeposit) != nil)
    }

    @Test func aDeductedDepositDraws() throws {
        let (model, deposit, _) = try deductedDeposit()
        model.openInvoice(deposit)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "invoice-editor-deducted")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    // MARK: A refused save opens nothing

    @Test func aRefusedSaveLeavesNothingOpen() throws {
        let model = try UIFixture.sampleModel()
        // A library file that can't be read is never overwritten, so every save is refused.
        try Data("not a library".utf8).write(to: model.store.libraryURL)
        let count = model.library.invoices.count
        let q1 = try #require(model.library.quote(number: "Q-0001")).id
        let care = try invoice(model, "INV-0002").id
        let attempts: [(name: String, run: () -> Void)] = [
            ("newInvoice", { model.newInvoice() }),
            ("draftInvoiceNow", { model.draftInvoiceNow(forQuote: q1) }),
            ("duplicateInvoice", { model.duplicateInvoice(care) }),
            ("completeJob", { model.completeJob(q1) }),
        ]
        for attempt in attempts {
            attempt.run()
            #expect(model.openInvoiceID == nil, "\(attempt.name) opened an invoice that wasn't saved")
            #expect(model.message != nil, "\(attempt.name) said nothing")
            #expect(model.library.invoices.count == count, "\(attempt.name) changed the library")
            model.message = nil
        }
        #expect(model.library.quote(q1)?.completedOn == nil)
    }

    // MARK: The headers fit the smallest window

    /// The header sits above the form and the preview, so it has the section's whole width, and the
    /// preview doesn't come off it. At the window's smallest (980) that is 980 less the section tree
    /// (190), the 4-pt gap beside it and the 4-pt padding either side: 778. The header's own 8-pt
    /// padding is inside the width measured. A header whose ideal width is more than 778 gets its
    /// buttons cut ("Send b…"). Measured when this was written: the widest quote header (six
    /// buttons) 717, a total in the millions 722, and every invoice header under 600.
    static let sectionWidth: CGFloat = 980 - 190 - 4 - 4 - 4

    func idealWidth<V: View>(_ view: V) -> CGFloat {
        _ = NSApplication.shared
        return NSHostingView(rootView: view).fittingSize.width
    }

    @Test func theQuoteHeaderFitsTheSmallestWindow() throws {
        func width(_ model: AppModel, _ number: String) throws -> CGFloat {
            let quote = try #require(model.library.quote(number: number))
            return idealWidth(QuoteEditorView(model: model, quoteID: quote.id).header(quote))
        }
        let sample = try UIFixture.sampleModel()
        // The widest action row: accepted and nothing invoiced yet gives six buttons, with Record
        // Acceptance… and Draft Invoice Now as well as Job Complete.
        var library = try SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date())
        var quote = library.newQuote(on: UIFixture.today, clientID: library.clients.first?.id)
        quote.addLine(LineItem(title: "Design", rate: Money(dollars: 600)))
        quote.addLine(LineItem(title: "Build", rate: Money(dollars: 1200)))
        try library.update(quote)
        try library.markSent(quote: quote.id)
        try library.recordAcceptance(Acceptance(source: .byHand, accepted: ["01", "02"], declined: []), forQuote: quote.id)
        let wideModel = try UIFixture.model(library)
        let wide = idealWidth(QuoteEditorView(model: wideModel, quoteID: quote.id).header(try #require(wideModel.library.quote(quote.id))))
        let draft = try width(sample, "Q-0004")
        #expect(wide > draft, "the six-button row should be the wider one, or this isn't measuring the buttons")
        #expect(wide <= Self.sectionWidth, "the quote header needs \(wide) pt of \(Self.sectionWidth)")
        for number in ["Q-0001", "Q-0002", "Q-0003", "Q-0004"] {
            let needed = try width(sample, number)
            #expect(needed <= Self.sectionWidth, "\(number)'s header needs \(needed) pt of \(Self.sectionWidth)")
        }
        // The longest top row: a completed job beside the status, and a total in the millions.
        let done = try UIFixture.sampleModel()
        let q1 = try #require(done.library.quote(number: "Q-0001")).id
        done.completeJob(q1)
        var big = try #require(done.library.quote(q1))
        big.lines[0].rate = Money(dollars: 3_000_000)   // three hours of it: $9,004,470.00 in all
        // Not saved (an invoiced quote's prices are locked): this only draws the header with that total.
        let bigWidth = idealWidth(QuoteEditorView(model: done, quoteID: q1).header(big))
        #expect(bigWidth <= Self.sectionWidth, "a total in the millions needs \(bigWidth) pt of \(Self.sectionWidth)")
    }

    @Test func theInvoiceHeaderFitsTheSmallestWindow() throws {
        let model = try UIFixture.sampleModel()
        func width(_ number: String) throws -> CGFloat {
            let found = try invoice(model, number)
            return idealWidth(InvoiceEditorView(model: model, invoiceID: found.id).header(found))
        }
        // Sent and unpaid: Send by Mail…, Void…, Duplicate and Save PDF…, with an overdue status.
        let sentOneOff = try width("INV-0002")
        let paid = try width("INV-0001")
        #expect(sentOneOff > paid, "the four-button row should be the wider one, or this isn't measuring the buttons")
        for number in ["INV-0001", "INV-0002", "INV-0003"] {
            let needed = try width(number)
            #expect(needed <= Self.sectionWidth, "\(number)'s header needs \(needed) pt of \(Self.sectionWidth)")
        }
        // A draft: Send by Mail…, Delete Draft, Duplicate and Save PDF….
        model.newInvoice()
        let draft = try #require(model.openInvoiceID.flatMap { model.library.invoice($0) })
        let draftWidth = idealWidth(InvoiceEditorView(model: model, invoiceID: draft.id).header(draft))
        #expect(draftWidth <= Self.sectionWidth, "a draft's header needs \(draftWidth) pt of \(Self.sectionWidth)")
    }
}
