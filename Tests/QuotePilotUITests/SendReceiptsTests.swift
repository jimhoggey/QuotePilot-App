import AppKit
import Foundation
import Testing
import QuotePilotCore
@testable import QuotePilotUI

/// Send Receipts: paid invoices for one client, chosen in the Invoices list, go out in one email with a
/// receipt each and the total paid.
@MainActor
@Suite struct SendReceiptsTests {
    /// The sample with two invoices for one client, sent and paid in full: INV-0004 Logo files $220 and
    /// INV-0005 Website updates $450.
    func model(mail: FakeMail = FakeMail()) throws -> (AppModel, [UUID]) {
        let model = try UIFixture.sampleModel(mail: mail)
        let client = try #require(model.library.clients.first { !$0.email.isEmpty })
        let ids = try [("Logo files", 220), ("Website updates", 450)].map { title, dollars in
            try invoice(in: model, for: client.id, title: title, dollars: dollars, paid: true)
        }
        return (model, ids)
    }

    /// A new invoice for `client`, sent and paid in full when `paid`, a draft otherwise.
    func invoice(in model: AppModel, for client: UUID, title: String, dollars: Int, paid: Bool) throws -> UUID {
        var id: UUID?
        _ = model.change("") { library in
            var invoice = library.newInvoice(on: model.today, clientID: client)
            invoice.title = title
            invoice.lines = [LineItem(title: title, rate: Money(dollars: dollars))]
            try library.update(invoice)
            if paid {
                try library.markSent(invoice: invoice.id)
                try library.recordPayment(Payment(date: model.today, amount: Money(dollars: dollars)), toInvoice: invoice.id)
            }
            id = invoice.id
        }
        return try #require(id)
    }

    @Test func onlyPaidInvoicesForOneClientGo() throws {
        let (model, ids) = try model()
        let client = try #require(model.library.invoice(ids[0])?.clientID)
        #expect(model.receiptsDocument(Set(ids)) == .receipts(ids))
        #expect(model.receiptsDocument([ids[0]]) == .receipt(ids[0]), "one goes on its own")
        #expect(model.receiptsDocument([]) == nil)

        let draft = try invoice(in: model, for: client, title: "Draft", dollars: 90, paid: false)
        #expect(model.receiptsDocument([ids[0], draft]) == nil, "only invoices with payments")
        let other = try #require(model.library.clients.first { $0.id != client })
        let theirs = try invoice(in: model, for: other.id, title: "Theirs", dollars: 90, paid: true)
        #expect(model.receiptsDocument([ids[0], theirs]) == nil, "two clients")
    }

    @Test func oneDraftCarriesEveryReceiptAndTheTotalPaid() throws {
        let mail = FakeMail()
        let (model, ids) = try model(mail: mail)
        model.send(.receipts(ids))
        let draft = try #require(mail.drafts.first)
        #expect(mail.drafts.count == 1)
        #expect(draft.attachments.count == 2)
        #expect(draft.attachments.map(\.lastPathComponent).allSatisfy { $0.hasPrefix("Receipt ") && $0.hasSuffix(".pdf") })
        #expect(draft.attachments.allSatisfy { $0.path.hasPrefix(model.sentFolder.path) })
        #expect(draft.subject == "Receipts from Sample Studio")
        #expect(draft.body.contains("Attached are 2 receipts:"))
        #expect(draft.body.contains("• INV-0004, Logo files, $220.00 paid"))
        #expect(draft.body.contains("• INV-0005, Website updates, $450.00 paid"))
        #expect(draft.body.contains("Total paid: $670.00."))
        #expect(model.message?.text.hasPrefix("Quote Pilot opened a Mail draft of the receipts for INV-0004 and INV-0005") == true)
    }

    @Test func yesMarksEveryReceiptSentAndNotYetNone() throws {
        let (model, ids) = try model()
        model.send(.receipts(ids))
        model.respond(try #require(model.message?.choices.first { $0.isCancel }))
        #expect(ids.allSatisfy { model.library.invoice($0)?.receiptSentAt == nil })

        model.send(.receipts(ids))
        model.respond(try #require(model.message?.choices.first { $0.isDefault }))
        #expect(ids.allSatisfy { model.library.invoice($0)?.receiptSentAt != nil })
        #expect(model.section == .dashboard)
    }

    /// Once the receipts have gone the list says Receipt sent, and Find "paid" still finds them.
    @Test func sentReceiptsShowInTheListAndPaidStillFindsThem() throws {
        let (model, ids) = try model()
        model.send(.receipts(ids))
        model.respond(try #require(model.message?.choices.first { $0.isDefault }))
        model.findText[.invoices] = "paid"
        let rows = InvoicesView.visibleRows(model).filter { ids.contains($0.id) }
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.status == .receiptSent && $0.status.listLabel == "Receipt sent" })
    }

    @Test func theMenuSaysHowMany() {
        #expect(InvoicesView.sendReceiptsTitle(1) == "Send Receipt…")
        #expect(InvoicesView.sendReceiptsTitle(3) == "Send 3 Receipts…")
    }

    /// ⌘-click taking a row out leaves the selection on a row still chosen, or on none; ⇧-click keeps it
    /// on the anchor; any other click moves it to the row.
    @Test func theSelectionStaysOnAChosenRow() {
        let ids = ["a", "b", "c"]
        let select = { (row: String, chosen: Set<String>, anchor: String?, modifiers: NSEvent.ModifierFlags) in
            DetailsLayout.selection(clicking: row, in: ids, chosen: chosen, anchor: anchor, modifiers: modifiers)
        }
        #expect(select("c", ["c"], "a", []) == "c")
        #expect(select("c", ["a", "c"], "a", .command) == "c")
        #expect(select("c", ["a"], "c", .command) == "a", "the row taken out was the selection")
        #expect(select("c", ["a", "b"], "b", .command) == "b")
        #expect(select("c", [], "c", .command) == nil)
        #expect(select("c", ["a", "b", "c"], "a", .shift) == "a")
    }

    /// Libraries from before Send Receipts get the standard wording for it.
    @Test func anOlderLibraryGetsTheStandardWording() throws {
        let old = #"{"receipt":{"subject":"R","body":"B"},"together":{"subject":"T","body":"B"}}"#
        let templates = try JSONDecoder().decode(EmailTemplates.self, from: Data(old.utf8))
        #expect(templates.receipt.subject == "R")
        #expect(templates.receipts == EmailTemplates.standard.receipts)
    }
}
