import AppKit
import Foundation
import SwiftUI
import Testing
import QuotePilotCore
@testable import QuotePilotUI

@MainActor
@Suite struct PaymentTests {
    /// INV-0003: hosting and support, $195, $60 paid, $135 owing.
    func hosting(_ model: AppModel) throws -> Invoice {
        try #require(model.library.invoices.first { $0.number == "INV-0003" })
    }

    /// A clock the test moves by hand, so "the next save" can really be later than the note.
    final class Clock {
        var time: Date
        init(_ time: Date) { self.time = time }
    }

    // MARK: Recording

    @Test func recordingAPaymentLowersWhatsOwing() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        var entry = try #require(model.newPaymentEntry(for: invoice.id))
        #expect(entry.amount == "$135.00")
        #expect(entry.date == UIFixture.today)
        entry.method = .card
        entry.note = "Paid at the office"
        #expect(model.recordPayment(entry))
        let paid = try #require(model.library.invoice(invoice.id))
        #expect(paid.owing == .zero)
        #expect(paid.payments.last?.method == .card)
        #expect(paid.payments.last?.note == "Paid at the office")
        // Nothing pops up: the figures on screen changed, and the status bar says what was recorded.
        #expect(model.message == nil)
        #expect(model.dialog == nil)
        #expect(model.statusNote?.text == "Recorded $135.00 for INV-0003")
    }

    @Test func aPartPaymentLeavesTheRestOwing() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        var entry = try #require(model.newPaymentEntry(for: invoice.id))
        entry.amount = "100"
        entry.note = "  Part, by cash  "
        #expect(model.recordPayment(entry))
        let paid = try #require(model.library.invoice(invoice.id))
        #expect(paid.owing == Money(dollars: 35))
        #expect(paid.payments.last?.note == "Part, by cash", "the note is trimmed")
        #expect(model.statusNote?.text == "Recorded $100.00 for INV-0003")
        // What's left is offered next time, so a second payment starts from $35.00.
        #expect(model.newPaymentEntry(for: invoice.id)?.amount == "$35.00")
    }

    @Test func thePaymentButtonOpensTheInvoice() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        model.section = .dashboard
        model.startPayment(invoice.id)
        #expect(model.section == .invoices)
        #expect(model.openInvoiceID == invoice.id)
        #expect(model.message == nil)
        #expect(model.dialog == nil)
    }

    @Test func aPaymentOverWhatsOwingIsRefused() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        var entry = try #require(model.newPaymentEntry(for: invoice.id))
        entry.amount = "500"
        #expect(!model.recordPayment(entry))
        #expect(model.message?.text == LibraryError.paymentMoreThanOwing(Money(dollars: 135)).message)
        #expect(model.library.invoice(invoice.id)?.payments.count == 1)
        #expect(model.statusNote == nil)
    }

    @Test func aPaymentOfNothingIsRefused() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        var entry = try #require(model.newPaymentEntry(for: invoice.id))
        entry.amount = "0"
        #expect(!model.recordPayment(entry))
        #expect(model.message?.text == LibraryError.paymentNotPositive.message)
        #expect(model.library.invoice(invoice.id)?.payments.count == 1)
    }

    @Test func aHalfTypedAmountIsRefused() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        var entry = try #require(model.newPaymentEntry(for: invoice.id))
        entry.amount = "12.3.4"
        #expect(!model.recordPayment(entry))
        #expect(model.message?.title == "Amount")
        #expect(model.library.invoice(invoice.id)?.payments.count == 1)
        #expect(model.statusNote == nil)
    }

    // MARK: What can take a payment

    @Test func onlySentInvoicesWithMoneyOwingTakePayments() throws {
        let model = try UIFixture.sampleModel()
        let deposit = try #require(model.library.invoices.first { $0.number == "INV-0001" })
        model.openInvoice(deposit.id)
        #expect(model.payableInvoiceID == nil, "paid in full")
        #expect(model.newPaymentEntry(for: deposit.id) == nil)
        model.newInvoice()
        let draft = try #require(model.openInvoiceID)
        #expect(model.payableInvoiceID == nil, "a draft")
        #expect(model.newPaymentEntry(for: draft) == nil)
        model.startPayment(draft)
        #expect(model.dialog == nil)
        #expect(model.message?.text == LibraryError.notSent.message)
    }

    @Test func aVoidInvoiceTakesNoPayments() throws {
        let model = try UIFixture.sampleModel()
        let care = try #require(model.library.invoices.first { $0.number == "INV-0002" })
        model.voidInvoice(care.id)
        model.respond(try #require(model.message?.choices.first { $0.title == "Void" }))
        model.openInvoice(care.id)
        #expect(model.payableInvoiceID == nil)
        #expect(model.newPaymentEntry(for: care.id) == nil)
        model.startPayment(care.id)
        #expect(model.message?.text == LibraryError.isVoid.message)
    }

    /// The toolbar's Payment button: the open invoice, or the selected one in the list, and only on
    /// the Invoices screen.
    @Test func theToolbarPaymentButtonFollowsTheOpenOrSelectedInvoice() throws {
        let model = try UIFixture.sampleModel()
        let hosting = try hosting(model)
        let care = try #require(model.library.invoices.first { $0.number == "INV-0002" })
        #expect(model.payableInvoiceID == nil, "the Dashboard has no invoice")
        model.section = .invoices
        model.selectedInvoiceID = care.id
        #expect(model.payableInvoiceID == care.id, "the list's selection")
        model.openInvoiceID = hosting.id
        #expect(model.payableInvoiceID == hosting.id, "the open invoice wins")
        model.openInvoiceID = UUID()
        #expect(model.payableInvoiceID == care.id, "an open invoice that is gone falls back to the selection")
        model.section = .quotes
        #expect(model.payableInvoiceID == nil)
    }

    // MARK: Removing

    @Test func removingAPaymentAsksFirst() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        let payment = try #require(invoice.payments.first)
        model.removePayment(payment.id, from: invoice.id)
        #expect(model.library.invoice(invoice.id)?.payments.count == 1)
        model.respond(try #require(model.message?.choices.first { $0.title == "Remove" }))
        #expect(model.library.invoice(invoice.id)?.payments.isEmpty == true)
    }

    @Test func removingTheLastPaymentClearsTheReceipt() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        model.change("test") { try $0.markReceiptSent(invoice: invoice.id) }
        let payment = try #require(invoice.payments.first)
        model.removePayment(payment.id, from: invoice.id)
        model.respond(try #require(model.message?.choices.first { $0.title == "Remove" }))
        #expect(model.library.invoice(invoice.id)?.receiptSentAt == nil)
    }

    /// A receipt covers the payments up to when it was sent; a new payment makes the box offer
    /// Send Receipt… again, with no "Receipt sent" line left over.
    @Test func aNewPaymentClearsTheReceiptSoItCanBeSentAgain() throws {
        let model = try UIFixture.sampleModel()
        let invoice = try hosting(model)
        model.change("test") { try $0.markReceiptSent(invoice: invoice.id) }
        #expect(model.library.invoice(invoice.id)?.receiptSentAt != nil)
        var entry = try #require(model.newPaymentEntry(for: invoice.id))
        entry.amount = "$10.00"
        #expect(model.recordPayment(entry))
        #expect(model.library.invoice(invoice.id)?.receiptSentAt == nil)
        #expect(model.library.invoice(invoice.id)?.payments.count == 2)
    }

    // MARK: The status-bar note

    @Test func theStatusBarShowsTheNoteUntilTheNextSave() throws {
        let dashboard = Dashboard(library: Library(), today: UIFixture.today)
        let saved = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 14, minute: 41))!
        let text = "Recorded $135.00 for INV-0003"

        // Made after the last save, or at the same moment: the note shows in the last cell.
        let after = StatusNote(text: text, at: saved.addingTimeInterval(5))
        #expect(StatusBarText.items(dashboard, lastSaved: saved, note: after, currencyCode: "AUD")[3] == text)
        let same = StatusNote(text: text, at: saved)
        #expect(StatusBarText.items(dashboard, lastSaved: saved, note: same, currencyCode: "AUD")[3] == text)
        // Nothing saved yet: the note still shows.
        #expect(StatusBarText.items(dashboard, lastSaved: nil, note: after, currencyCode: "AUD")[3] == text)

        // A save since the note replaces it with the time of that save.
        let before = StatusNote(text: text, at: saved.addingTimeInterval(-5))
        #expect(StatusBarText.items(dashboard, lastSaved: saved, note: before, currencyCode: "AUD")[3].hasPrefix("Saved 2:41"))
        // No note at all, as before.
        #expect(StatusBarText.items(dashboard, lastSaved: saved, note: nil, currencyCode: "AUD")[3].hasPrefix("Saved 2:41"))
        #expect(StatusBarText.items(dashboard, lastSaved: nil, note: nil, currencyCode: "AUD")[3] == "No changes yet")
        // The other three cells never change.
        #expect(Array(StatusBarText.items(dashboard, lastSaved: saved, note: after, currencyCode: "AUD").prefix(3))
                == Array(StatusBarText.items(dashboard, lastSaved: saved, note: nil, currencyCode: "AUD").prefix(3)))
    }

    /// The same thing through the model: the note a payment leaves is replaced by the next change that saves.
    @Test func theNextChangeThatSavesReplacesTheNote() throws {
        let clock = Clock(UIFixture.today.date())
        let store = LibraryStore(folder: UIFixture.makeFolder())
        try store.save(SampleLibrary.make(today: UIFixture.today, now: UIFixture.today.date()))
        let model = AppModel(store: store, now: { clock.time }, mail: FakeMail(), sentFolder: UIFixture.makeFolder())
        let invoice = try hosting(model)
        clock.time = clock.time.addingTimeInterval(60)
        model.recordPayment(try #require(model.newPaymentEntry(for: invoice.id)))
        let note = try #require(model.statusNote)
        #expect(note.at == clock.time)
        #expect(StatusBarText.items(model.dashboard, lastSaved: model.lastSaved, note: model.statusNote, currencyCode: "AUD")[3]
                == "Recorded $135.00 for INV-0003")
        clock.time = clock.time.addingTimeInterval(60)
        model.newClient()
        #expect(model.lastSaved == clock.time)
        #expect(StatusBarText.items(model.dashboard, lastSaved: model.lastSaved, note: model.statusNote, currencyCode: "AUD")[3]
                .hasPrefix("Saved"))
    }

    // MARK: Drawing

    @Test func thePaymentsBoxDraws() throws {
        let model = try UIFixture.sampleModel()
        model.openInvoice(try hosting(model).id)
        let rep = Snapshot.render(RootView(model: model), size: CGSize(width: 1240, height: 800), name: "invoice-payments")
        #expect(rep.map(Snapshot.hasContent) == true)
    }

    /// The New payment area needs 500 pt less the form's 6-pt right padding, so every name in it
    /// (Date:, Amount:, Method:, Note:, Record Payment) fits whole when the editor is at its narrowest.
    /// This measures the whole box, group-box padding included.
    @Test func thePaymentsBoxFitsTheEditorFormAtItsNarrowest() throws {
        func width(_ model: AppModel, _ number: String) throws -> CGFloat {
            let invoice = try #require(model.library.invoices.first { $0.number == number })
            return idealWidth(PaymentsBox(model: model, invoice: invoice).groupBoxStyle(.win95))
        }
        let model = try UIFixture.sampleModel()
        let owing = try width(model, "INV-0002")
        let part = try width(model, "INV-0003")
        let paid = try width(model, "INV-0001")
        #expect(owing > paid, "the box with a New payment area should be the wider one, or this isn't measuring it")
        for needed in [owing, part, paid] {
            #expect(needed <= 500 - 6, "the Payments box needs \(needed) pt of 494")
        }
    }

    func idealWidth<V: View>(_ view: V) -> CGFloat {
        _ = NSApplication.shared
        return NSHostingView(rootView: view).fittingSize.width
    }
}
